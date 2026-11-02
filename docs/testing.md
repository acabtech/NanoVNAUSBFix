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

## Host USB permissions

libusb needs write access to the raw USB device node. Install the rule once:

```bash
sudo scripts/install-udev.sh
```

If the instrument is still inaccessible, unplug and replug it. Remove the rule
with:

```bash
sudo scripts/uninstall-udev.sh
```

The rule matches the NanoVNA VID/PID (`0483:5740`) and grants the active seat
user plus the `uucp` group access. It covers both CDC and USBTMC interfaces, so
`riglol scpi --usb` and the CDC shell both work without root.

## Release baselines

The v0.1.0 artifacts are the reference point for v0.2.0. Official firmware is
frozen: it may only change for a confirmed USB bug with a reproduction and a
regression test. The unofficial image has room to grow for v0.2.0 but must stay
under the budget enforced by [`scripts/verify.sh`](../scripts/verify.sh:10).

| Flavor | v0.1.0 image size | v0.1.0 `.bin` SHA-256 | Budget |
| --- | --- | --- | --- |
| Official (`USB-PCLK`) | 91,704 bytes | `2148dc2638a469a6d9893518f73daca9d8b104c952671611af9f3798efe9dbc2` | 92,160 bytes |
| Unofficial (`USBTMC`) | 95,432 bytes | `b472d71bf94c1fd49d9f6b8fa5813198d181508cfc03d0ef62c0b740822a5300` | 122,880 bytes |

The v0.1.0 SCPI command contract and the read-only baseline transcript live in
[`testing/v0.1.0-scpi-baseline.md`](v0.1.0-scpi-baseline.md). Re-record the
transcript on hardware whenever the USBTMC framing or command surface changes,
and diff it against the previous release.

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
