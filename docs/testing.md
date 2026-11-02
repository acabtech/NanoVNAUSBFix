# Testing

## Automated (CI)

`scripts/verify.sh` runs after every build and checks:

- both `.bin`, `.hex`, `.elf` and `SHA256SUMS` exist;
- the `.bin` is no larger than the 128 KiB STM32F072 flash;
- the `SHA256SUMS` files validate;
- the unofficial ELF contains `usbtmc_process`, `usbtmc_configure` and
  `vna_usb_scpi_exec`;
- the official ELF does **not** contain the USBTMC bridge.

CI also rebuilds from a clean cache, so a broken patch or a changed upstream
tarball fails the run.

## Hardware smoke test (recommended)

Use a NanoVNA-H with the unofficial image and a host with libusb access.

### 1. Enumeration

```bash
lsusb -d 0483:5740 -v | grep -E 'bInterfaceClass|bInterfaceSubClass'
```

Expect both a CDC interface and a `0xfe`/`0x03` USBTMC interface.

### 2. Identify

```bash
riglol usb list
riglol scpi --usb usb:0x0483:0x5740 '*IDN?'
```

### 3. Sweep and data

```bash
riglol scpi --usb usb:0x0483:0x5740 ':VNA:SWE:START 1000000'
riglol scpi --usb usb:0x0483:0x5740 ':VNA:SWE:STOP 30000000'
riglol scpi --usb usb:0x0483:0x5740 ':VNA:SWE:POINTS 101'
riglol scpi --usb usb:0x0483:0x5740 ':VNA:SWE:EXEC'
riglol scpi --usb usb:0x0483:0x5740 ':VNA:DATA:CHUNK? 0,0,4'
```

The data should change when you attach a known load (50 Ω, open, short) to the
port, and `:VNA:DATA:CHUNK? 1,...` should show S21.

### 4. CDC regression

Confirm the stock shell still works:

```bash
picocom -b 115200 /dev/ttyACM0
# press Enter, then:
info
version
```

### 5. Recovery check

Re-enter DFU and flash the official image. This proves the fallback path works
on your unit.

## Manual regression matrix

| Check | Official | Unofficial |
| --- | --- | --- |
| Enumerates as `0483:5740` | required | required |
| CDC shell works | required | required |
| USBTMC interface present | — | required |
| `*IDN?` over USBTMC | — | required |
| Sweep + data over USBTMC | — | required |
| Display does not remain frozen after a query | — | required |
| Reflash over DFU | required | required |

If you find a failure, open an issue with the output of `lsusb -v`, `dmesg`,
the firmware asset name and the exact command sequence.
