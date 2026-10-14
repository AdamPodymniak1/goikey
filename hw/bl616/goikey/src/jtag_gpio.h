#ifndef JTAG_GPIO_H
#define JTAG_GPIO_H

#include <stdint.h>
#include <stdbool.h>

void jtag_gpio_init(void);

void jtag_transfer(uint16_t bits, const uint8_t *tdi, uint8_t *tdo);

void jtag_set_tck(bool value);
void jtag_set_tdi(bool value);
void jtag_set_tms(bool value);
void jtag_set_trst(bool value);
void jtag_set_srst(bool value);

bool jtag_get_tdo(void);

bool jtag_strobe(uint8_t pulses, bool tms, bool tdi);

void jtag_set_frequency(uint16_t kHz);

#endif
