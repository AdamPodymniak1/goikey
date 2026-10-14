/*
 * GPIO bit-bang JTAG engine for BL616 (Tang Nano 20K)
 *
 * Pin assignments (Nano20K):
 *   TMS = GPIO16, TCK = GPIO10, TDI = GPIO12, TDO = GPIO14
 *
 * Uses direct register access for inner-loop performance.
 * Reference: firmware-bl616/fpga/programmer.cpp
 */
#include "jtag_gpio.h"
#include "bflb_gpio.h"

/* GPIO config register addresses for Nano20K JTAG pins */
static volatile uint32_t *reg_tms = (volatile uint32_t *)0x20000904;  /* GPIO16 */
static volatile uint32_t *reg_tck = (volatile uint32_t *)0x200008ec;  /* GPIO10 */
static volatile uint32_t *reg_tdi = (volatile uint32_t *)0x200008f4;  /* GPIO12 */
static volatile uint32_t *reg_tdo = (volatile uint32_t *)0x200008fc;  /* GPIO14 */

#define GPIO_SET   (1 << 25)
#define GPIO_CLEAR (1 << 26)
#define GPIO_READ  (1 << 28)

static volatile uint32_t jtag_delay = 0;

static inline void delay_loop(void)
{
    volatile uint32_t n = jtag_delay;
    while (n--) {
        __asm__ volatile("nop");
    }
}

void jtag_gpio_init(void)
{
    struct bflb_device_s *gpio = bflb_device_get_by_name("gpio");

    bflb_gpio_init(gpio, GPIO_PIN_16, GPIO_OUTPUT | GPIO_FLOAT | GPIO_SMT_EN | GPIO_DRV_3);
    bflb_gpio_init(gpio, GPIO_PIN_10, GPIO_OUTPUT | GPIO_FLOAT | GPIO_SMT_EN | GPIO_DRV_3);
    bflb_gpio_init(gpio, GPIO_PIN_12, GPIO_OUTPUT | GPIO_FLOAT | GPIO_SMT_EN | GPIO_DRV_3);
    bflb_gpio_init(gpio, GPIO_PIN_14, GPIO_INPUT  | GPIO_FLOAT | GPIO_SMT_EN | GPIO_DRV_3);

    /* Start with TCK and TMS low */
    *reg_tck |= GPIO_CLEAR;
    *reg_tms |= GPIO_CLEAR;
    *reg_tdi |= GPIO_CLEAR;
}

void jtag_transfer(uint16_t bits, const uint8_t *tdi, uint8_t *tdo)
{
    for (uint16_t i = 0; i < bits; i++) {
        uint8_t bitmask = 0x80 >> (i & 7);

        /* Set TDI */
        if (tdi[i >> 3] & bitmask) {
            *reg_tdi |= GPIO_SET;
        } else {
            *reg_tdi |= GPIO_CLEAR;
        }

        /* TCK low */
        *reg_tck |= GPIO_CLEAR;
        delay_loop();

        /* TCK high */
        *reg_tck |= GPIO_SET;
        delay_loop();

        /* Read TDO */
        if (tdo) {
            if (*reg_tdo & GPIO_READ) {
                tdo[i >> 3] |= bitmask;
            }
        }
    }

    /* Leave TCK low */
    *reg_tck |= GPIO_CLEAR;
}

void jtag_set_tck(bool value)
{
    *reg_tck |= value ? GPIO_SET : GPIO_CLEAR;
}

void jtag_set_tdi(bool value)
{
    *reg_tdi |= value ? GPIO_SET : GPIO_CLEAR;
}

void jtag_set_tms(bool value)
{
    *reg_tms |= value ? GPIO_SET : GPIO_CLEAR;
}

void jtag_set_trst(bool value)
{
    /* TRST not connected on Tang Nano 20K — no-op */
    (void)value;
}

void jtag_set_srst(bool value)
{
    /* SRST not connected on Tang Nano 20K — no-op */
    (void)value;
}

bool jtag_get_tdo(void)
{
    return (*reg_tdo & GPIO_READ) != 0;
}

bool jtag_strobe(uint8_t pulses, bool tms, bool tdi)
{
    *reg_tms |= tms ? GPIO_SET : GPIO_CLEAR;
    *reg_tdi |= tdi ? GPIO_SET : GPIO_CLEAR;

    bool last_tdo = false;
    for (uint8_t i = 0; i < pulses; i++) {
        *reg_tck |= GPIO_CLEAR;
        delay_loop();
        *reg_tck |= GPIO_SET;
        delay_loop();
        last_tdo = (*reg_tdo & GPIO_READ) != 0;
    }
    *reg_tck |= GPIO_CLEAR;

    return last_tdo;
}

void jtag_set_frequency(uint16_t kHz)
{
    if (kHz == 0) {
        jtag_delay = 0;
        return;
    }
    /*
     * Rough estimate: BL616 runs at ~320MHz.
     * Each delay iteration ~3 cycles (loop + nop).
     * For frequency f: half-period = 1/(2f), cycles = 320M/(2f*1000) / 3
     */
    uint32_t target = 320000 / (2 * (uint32_t)kHz * 3);
    jtag_delay = (target > 1) ? target : 0;
}
