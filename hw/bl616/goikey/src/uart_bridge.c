/*
 * CDC-ACM to UART1 bridge for BL616 (GoiKey: link to the FPGA crypto accelerator)
 *
 * A vendor bulk interface (EP 0x03 OUT / 0x84 IN) bridges to hardware UART1 at a fixed 1.5 Mbaud (the FPGA link).
 * Both directions are interrupt driven so 1.5 Mbaud streams survive the 32-byte UART FIFOs:
 *   UART RX  : FIFO-threshold / RX-timeout interrupt -> rx ring -> task -> USB IN
 *   USB OUT  : endpoint callback -> tx ring -> TX-FIFO interrupt -> UART TX
 * The OUT endpoint is only re-armed while the tx ring can take a whole transfer (the host is NAKed otherwise).
 *
 * Pin assignments (Nano20K):
 *   UART1_TX = GPIO11 (-> FPGA pin 70), UART1_RX = GPIO13 (<- FPGA pin 69)
 */
#include <string.h>
#include "usbd_core.h"
#include "bflb_uart.h"
#include "bflb_irq.h"
#include "bflb_gpio.h"
#include "FreeRTOS.h"
#include "task.h"
#include "uart_bridge.h"

#define CDC_OUT_EP  0x03
#define CDC_IN_EP   0x84

static struct bflb_device_s *uart1_dev;

/* OUT reads are one max-size packet (64 B, see usb_descriptors.c): the BL616 driver only completes an OUT transfer
 * when its buffer is full, so a longer buffer would hold short packets back until 512 bytes had accumulated. */
#define CDC_OUT_MPS 64u
static USB_NOCACHE_RAM_SECTION USB_MEM_ALIGNX uint8_t cdc_rx_buf[CDC_OUT_MPS];
static USB_NOCACHE_RAM_SECTION USB_MEM_ALIGNX uint8_t cdc_tx_buf[512];

static volatile bool cdc_configured;                     /* USB configured (no DTR without CDC) */
static volatile bool cdc_tx_busy;
static uint32_t debug_rx_bytes;
static uint32_t debug_tx_bytes;
#define LINK_BAUD 1500000u                              /* = accel_top CPB 18 at 27 MHz */
static uint32_t debug_baudrate = LINK_BAUD;

#define RING 4096u                                      /* power of two */
static uint8_t txr[RING], rxr[RING];
static volatile uint32_t txr_head, txr_tail;            /* USB OUT ISR writes head, UART ISR reads tail */
static volatile uint32_t rxr_head, rxr_tail;            /* UART ISR writes head, task reads tail */
static volatile uint32_t rx_overflow;
static volatile bool out_armed = true;                  /* cleared only by the OUT callback */
static volatile bool usb_ready;

static inline uint32_t txr_free(void) { return RING - (txr_head - txr_tail); }

/* ---------------- UART interrupt: RX into rxr, TX from txr ---------------- */
static void uart_isr(int irq, void *arg)
{
    (void)irq;
    (void)arg;
    uint32_t st = bflb_uart_get_intstatus(uart1_dev);

    if (st & (UART_INTSTS_RX_FIFO | UART_INTSTS_RTO)) {
        uint32_t h = rxr_head;
        while (bflb_uart_rxavailable(uart1_dev)) {
            uint8_t c = (uint8_t)bflb_uart_getchar(uart1_dev);
            if (h - rxr_tail < RING) rxr[h++ & (RING - 1)] = c;
            else rx_overflow++;
        }
        rxr_head = h;
        if (st & UART_INTSTS_RTO)
            bflb_uart_int_clear(uart1_dev, UART_INTCLR_RTO);
    }
    if (st & UART_INTSTS_TX_FIFO) {
        uint32_t t = txr_tail;
        while (t != txr_head && bflb_uart_txready(uart1_dev))
            bflb_uart_putchar(uart1_dev, txr[t++ & (RING - 1)]);
        txr_tail = t;
        if (t == txr_head)
            bflb_uart_txint_mask(uart1_dev, true);         /* nothing left: stop the FIFO-empty interrupt */
    }
}

/* ---------------- USB endpoints ---------------- */
static void cdc_bulk_out_cb(uint8_t busid, uint8_t ep, uint32_t nbytes)
{
    (void)busid;
    (void)ep;

    uint32_t h = txr_head;
    for (uint32_t i = 0; i < nbytes; i++)
        txr[(h + i) & (RING - 1)] = cdc_rx_buf[i];
    txr_head = h + nbytes;
    debug_tx_bytes += nbytes;
    if (nbytes)
        bflb_uart_txint_mask(uart1_dev, false);          /* the TX interrupt drains the ring */

    if (txr_free() >= CDC_OUT_MPS)
        usbd_ep_start_read(0, CDC_OUT_EP, cdc_rx_buf, CDC_OUT_MPS);
    else
        out_armed = false;                               /* the task re-arms once the ring has drained */
}

static void cdc_bulk_in_cb(uint8_t busid, uint8_t ep, uint32_t nbytes)
{
    (void)busid;
    (void)ep;
    (void)nbytes;
    cdc_tx_busy = false;
}

static struct usbd_endpoint cdc_out_ep = {
    .ep_addr = CDC_OUT_EP,
    .ep_cb = cdc_bulk_out_cb,
};

static struct usbd_endpoint cdc_in_ep = {
    .ep_addr = CDC_IN_EP,
    .ep_cb = cdc_bulk_in_cb,
};

static struct usbd_interface link_intf;

void uart_bridge_usb_init(uint8_t busid)
{
    usbd_add_interface(busid, &link_intf);
    usbd_add_endpoint(busid, &cdc_out_ep);
    usbd_add_endpoint(busid, &cdc_in_ep);
}

static void uart_config(uint32_t baud, uint8_t data_bits, uint8_t stop_bits, uint8_t parity)
{
    struct bflb_uart_config_s cfg = {
        .baudrate = baud,
        .direction = UART_DIRECTION_TXRX,
        .data_bits = data_bits,
        .stop_bits = stop_bits,
        .parity = parity,
        .bit_order = UART_LSB_FIRST,
        .flow_ctrl = 0,
        .tx_fifo_threshold = 7,
        .rx_fifo_threshold = 7,
    };
    bflb_irq_disable(uart1_dev->irq_num);
    bflb_uart_init(uart1_dev, &cfg);
    bflb_uart_txint_mask(uart1_dev, txr_tail == txr_head);
    bflb_uart_rxint_mask(uart1_dev, false);
    bflb_irq_enable(uart1_dev->irq_num);
    debug_baudrate = baud;
}

void uart_bridge_uart_init(void)
{
    struct bflb_device_s *gpio = bflb_device_get_by_name("gpio");

    bflb_gpio_uart_init(gpio, GPIO_PIN_11, GPIO_UART_FUNC_UART1_TX);
    bflb_gpio_uart_init(gpio, GPIO_PIN_13, GPIO_UART_FUNC_UART1_RX);

    uart1_dev = bflb_device_get_by_name("uart1");
    bflb_irq_attach(uart1_dev->irq_num, uart_isr, NULL);
    uart_config(LINK_BAUD, UART_DATA_BITS_8, UART_STOP_BITS_1, UART_PARITY_NONE);
}

void uart_bridge_start(void)
{
    txr_head = txr_tail = 0;
    rxr_head = rxr_tail = 0;
    out_armed = true;
    usb_ready = true;
    cdc_configured = true;
    cdc_tx_busy = false;
    usbd_ep_start_read(0, CDC_OUT_EP, cdc_rx_buf, CDC_OUT_MPS);
}

/* FreeRTOS task: forward the rx ring to USB IN, re-arm the OUT endpoint, apply line coding */
void uart_task(void *param)
{
    (void)param;

    for (;;) {
        if (uart1_dev == NULL) {
            vTaskDelay(1);
            continue;
        }

        if (usb_ready && !out_armed && txr_free() >= CDC_OUT_MPS) {
            uintptr_t flag = bflb_irq_save();
            if (!out_armed) {
                out_armed = true;
                usbd_ep_start_read(0, CDC_OUT_EP, cdc_rx_buf, CDC_OUT_MPS);
            }
            bflb_irq_restore(flag);
        }

        uint32_t n = rxr_head - rxr_tail;
        if (n && !cdc_tx_busy) {
            if (n > sizeof(cdc_tx_buf)) n = sizeof(cdc_tx_buf);
            uint32_t t = rxr_tail;
            for (uint32_t i = 0; i < n; i++)
                cdc_tx_buf[i] = rxr[(t + i) & (RING - 1)];
            rxr_tail = t + n;
            debug_rx_bytes += n;
            if (cdc_configured) {
                cdc_tx_busy = true;
                usbd_ep_start_write(0, CDC_IN_EP, cdc_tx_buf, n);
            }
            continue;                                        /* more may be waiting: no sleep */
        }
        vTaskDelay(1);
    }
}

void uart_bridge_get_debug(struct uart_debug_state *state)
{
    state->rx_bytes = debug_rx_bytes;
    state->tx_bytes = debug_tx_bytes;
    state->cdc_configured = cdc_configured;
    state->cdc_tx_busy = cdc_tx_busy;
    state->baudrate = debug_baudrate;
}
