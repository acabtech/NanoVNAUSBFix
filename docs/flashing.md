# Flashing and recovery

## Enter DFU

1. Unplug USB.
2. Hold **BOOT0** to VDD (or use the CONFIG → DFU entry if the running
   firmware has it), then plug USB back in.
3. `lsusb` should show:

```
0483:df11 STMicroelectronics STM32 BOOTLOADER
```

## Flash

```bash
sudo dfu-util -d 0483:df11 -a 0 -s 0x08000000:leave \
  -D dist/official/NanoVNA-H-1.2.50-USB-PCLK.bin
```

or:

```bash
./scripts/flash.sh dist/official/NanoVNA-H-1.2.50-USB-PCLK.bin
```

The unofficial image uses the same address:

```bash
./scripts/flash.sh dist/unofficial/NanoVNA-H-1.2.50-USBTMC.bin
```

`dfu-util` reports the transfer and the device leaves DFU into the application.

## Verify

Official image (CDC only):

```bash
lsusb | grep 0483:5740
# 0483:5740 STMicroelectronics NanoVNA-H
dmesg | tail
# cdc_acm ... ttyACM0: USB ACM device
```

Unofficial image (CDC + USBTMC):

```bash
lsusb -t
# interface 2 should be class 0xfe / subclass 0x03
riglol usb list
# marks the interface as usbtmc
riglol scpi --usb usb:0x0483:0x5740 '*IDN?'
# NanoVNA-H,USBFix,1.2.50,00000000
```

## Recovery

If the display stays dark or USB does not enumerate:

1. Re-enter DFU with BOOT0 or the hardware strap.
2. Flash the official 1.2.50 image or the PCLK image again.
3. Do not interrupt power during the DFU write.

DFU mode is in ROM and cannot be bricked by a bad application image.

## After flashing

- Recalibrate; calibration lives in the config area and is preserved by a
  normal DFU write, but re-check it after changing firmware.
- On the unofficial image, the CDC shell and the USBTMC interface are both
  active. A tool that opens `/dev/ttyACM*` is not using USBTMC.
