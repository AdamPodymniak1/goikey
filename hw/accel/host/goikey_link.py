"""pyserial-like transport over the GoiKey (BL616) vendor bulk link to the FPGA accelerator.

The BL616 bridges USB interface 1 (EP 0x03 OUT / 0x84 IN) to the FPGA UART at a fixed 1.5 Mbaud.
Use the port name "goikey" with tro_accel.Accel / the self-tests.
"""
import time
import usb.core, usb.util

VID, PID = 0x1209, 0xC0CA
INTF, EP_OUT, EP_IN = 1, 0x03, 0x84

class GoiKeyLink:
    def __init__(self, timeout=5.0):
        self.dev = usb.core.find(idVendor=VID, idProduct=PID)
        if self.dev is None:
            raise IOError("GoiKey (1209:c0ca) not found")
        if self.dev.is_kernel_driver_active(INTF):
            self.dev.detach_kernel_driver(INTF)
        usb.util.claim_interface(self.dev, INTF)
        self.timeout = timeout
        self.buf = bytearray()

    def close(self):
        usb.util.release_interface(self.dev, INTF)
        usb.util.dispose_resources(self.dev)

    def write(self, data):
        # One max-size packet (64 B) per transfer: the BL616 driver re-arms its OUT DMA per packet, so a second packet
        # that arrives back-to-back within one transfer would be lost.
        data = bytes(data)
        for o in range(0, len(data), 64):
            self.dev.write(EP_OUT, data[o:o + 64], timeout=int(self.timeout * 1000) + 1000)
        return len(data)

    def _fill(self, ms):
        try:
            self.buf += bytes(self.dev.read(EP_IN, 512, timeout=max(1, ms)))
        except usb.core.USBTimeoutError:
            pass

    def read(self, n):
        t_end = time.monotonic() + self.timeout
        while len(self.buf) < n:
            left = t_end - time.monotonic()
            if left <= 0: break
            self._fill(int(min(left, 0.2) * 1000))
        d, self.buf = bytes(self.buf[:n]), self.buf[n:]
        return d

    def reset_input_buffer(self):
        self.buf = bytearray()
        for _ in range(4): self._fill(5)
        self.buf = bytearray()
