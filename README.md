[![CI](https://github.com/acabtech/NanoVNAUSBFix/actions/workflows/ci.yml/badge.svg)](https://github.com/acabtech/NanoVNAUSBFix/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/acabtech/NanoVNAUSBFix)](https://github.com/acabtech/NanoVNAUSBFix/releases/latest)

# NanoVNA USBFix

Firmware builds for the **NanoVNA-H (STM32F072)** that make USB enumeration
reliable, plus an optional build that exposes the VNA as a **USBTMC/SCPI
instrument** that [omariglol](https://github.com/acabtech/omariglol) can drive
through its generic USB layer.

The project is deliberately small: upstream NanoVNA-H firmware is pinned,
patched, built and released from this repository. No fork of the upstream tree
is maintained.

## Firmware flavors

| Release asset | What it is | USB interface |
| --- | --- | --- |
| `NanoVNA-H-1.2.50-USB-PCLK.bin` | **Official build.** Stock NanoVNA-H 1.2.50 with the USB peripheral clocked from PCLK instead of HSI48. | CDC ACM serial (`0483:5740`), the normal NanoVNA shell |
| `NanoVNA-H-1.2.50-USBTMC.bin` | **Unofficial build.** The same PCLK fix plus a composite CDC + USBTMC/SCPI interface. | CDC ACM **and** USBTMC (`0483:5740`, interface class `0xFE`/`0x03`) |

Both images are built from upstream tag [`1.2.50`](https://github.com/hugen79/NanoVNA-H/tree/1.2.50)
(commit `816495ebc8ca022149787ec2f9e058d6ce3bcb3b`). The only code changes are
the patches in [`patches/`](patches).

## Why PCLK?

The upstream application firmware selects the internal **HSI48** oscillator as
the USB clock. On some NanoVNA-H units that domain lets the device assert D+
but never delivers a usable USB core clock: the host sees a full-speed device,
control transfers fail, and enumeration does not complete. The ST ROM DFU
bootloader still enumerates, so the cable, connector and PHY are fine.

On the STM32F072 the USB peripheral can instead run from **PCLK**, the 48 MHz
PLL output the CPU already uses. Selecting `STM32_USBSW_PCLK` fixes enumeration
without trimming HSI48 through the CRS:

```c
/* NANOVNA_STM32_F072/mcuconf.h */
#define STM32_USBSW  STM32_USBSW_PCLK
```

An earlier experiment that enabled CRS auto-trim on HSI48 did not fix the
failure on the affected unit. It is kept for reference in
[`docs/experiments/crs-only.patch`](docs/experiments/crs-only.patch) and is not
built.

Result with the official build:

```
usb 1-4: New USB device found, idVendor=0483, idProduct=5740
usb 1-4: Product: NanoVNA-H
cdc_acm 1-4:1.0: ttyACM0: USB ACM device
```

## The unofficial USBTMC/SCPI build

`NanoVNA-H-1.2.50-USBTMC.bin` adds a second USB interface that speaks
**USBTMC** (USB Test & Measurement Class). It is the same transport omariglol
already implements in `omariglol-core::usb::usbtmc`, so the VNA appears as a
normal SCPI instrument rather than a serial port.

The CDC ACM interface is still present, so NanoVNA-Saver, the stock shell and
the existing workflows keep working. The USBTMC interface is additive.

```bash
# omariglol / riglol, from the omariglol repository
riglol usb list
riglol scpi --usb usb:0x0483:0x5740 '*IDN?'
# NanoVNA-H,USBFix,1.2.50,00000000

riglol scpi --usb usb:0x0483:0x5740 ':VNA:SWE:START 1000000'
riglol scpi --usb usb:0x0483:0x5740 ':VNA:SWE:STOP 30000000'
riglol scpi --usb usb:0x0483:0x5740 ':VNA:SWE:POINTS 101'
riglol scpi --usb usb:0x0483:0x5740 ':VNA:SWE:EXEC'
riglol scpi --usb usb:0x0483:0x5740 ':VNA:DATA:CHUNK? 0,0,16'
```

A generic escape hatch reaches the complete stock command set:

```bash
riglol scpi --usb usb:0x0483:0x5740 ':VNA:CMD? info'
riglol scpi --usb usb:0x0483:0x5740 ':VNA:CMD scan 1000000 30000000 101 0'
```

The matching `omariglol` driver profile (NanoVNA classifier, sweep/data
operations and the `19_nanovna.sh` example) lives on the
`feature/NanoVNAUSBFix` branch of
[`acabtech/omariglol`](https://github.com/acabtech/omariglol/tree/feature/NanoVNAUSBFix).

See [`docs/usb-api.md`](docs/usb-api.md) for the full command surface and
framing details.

## Flash

Put the NanoVNA in DFU mode (`lsusb` shows `0483:df11`), then:

```bash
make official          # or: make unofficial
sudo dfu-util -d 0483:df11 -a 0 -s 0x08000000:leave \
  -D dist/official/NanoVNA-H-1.2.50-USB-PCLK.bin
```

Or use the helper:

```bash
./scripts/flash.sh dist/official/NanoVNA-H-1.2.50-USB-PCLK.bin
```

Recovery is the same as stock: re-enter DFU (CONFIG → DFU, or short BOOT0 to
VDD) and flash a known-good image. See [`docs/flashing.md`](docs/flashing.md).

## Build from source

Requirements: `arm-none-eabi-gcc`, GNU make, `curl`, `tar`, `7z`, `patch`.
On Arch:

```bash
sudo pacman -S arm-none-eabi-gcc base-devel curl p7zip
```

Then:

```bash
make official      # build/ work tree, dist/official/ artifacts
make unofficial    # build/ work tree, dist/unofficial/ artifacts
make dist          # both, then verify
make clean
```

The upstream tarball is downloaded once into `build/cache` and verified against
a pinned SHA-256 before it is unpacked. `make` never modifies the repository
working tree; the patched source lives under `build/work/<flavor>`.

Release artifacts are produced by the `Release` GitHub workflow on a `v*` tag.
Each release carries `.bin`, `.hex`, `.elf`, `.map` and `SHA256SUMS` for both
flavors.

## Repository layout

```text
patches/                 pinned upstream patches
  0001-usb-clock-pclk.patch
  0002-usbtmc-scpi.patch
  optional-rtc-default-time.patch
plans/
  milestones.md          v0.1.0 baseline and v0.2.0 milestone plan
scripts/
  build.sh               fetch + patch + build one flavor
  fetch-upstream.sh      unpack the pinned tree for inspection
  verify.sh              artifact size/symbol/hash checks
  flash.sh               dfu-util helper
  install-udev.sh        grant USBTMC access to the active user
  uninstall-udev.sh      remove the USBTMC udev rule
  capture-scpi-baseline.sh  record the read-only SCPI contract
docs/
  architecture.md        USB clock and composite-device design
  usb-api.md             USBTMC/SCPI command reference
  building.md            toolchain and offline-build notes
  flashing.md            DFU and recovery
  testing.md             CI and hardware smoke tests
  testing/               recorded baseline transcripts
  experiments/           failed CRS experiment, kept for the record
.github/workflows/       CI and release automation
```

## Hardware scope

Target: **NanoVNA-H, STM32F072xB**, 128 KiB flash / 16 KiB RAM, upstream
firmware 1.2.50. The F303-based NanoVNA-H4 is not built here; its upstream
target is still available in the source tree, but no release artifact is
produced for it.

## Status and caveats

- The official PCLK image is the known-good fix from the original investigation.
- The USBTMC build compiles, fits comfortably in the F072 flash, and implements
  the USBTMC framing and SCPI surface described in the docs. A hardware
  enumeration/measurement smoke test is still recommended before relying on it
  in production; see [`docs/testing.md`](docs/testing.md).
- PCLK is the HSI-derived PLL, not a CRS-trimmed HSI48. It is reliable on the
  affected hardware, but HSI has looser absolute tolerance. If a unit becomes
  flaky over temperature, that is the first thing to revisit.
- The unofficial build is not an official NanoVNA release. Calibrate after
  flashing either image.

## License and provenance

Upstream NanoVNA-H firmware is GPL-3.0; this repository's patches and build
files are released under the same terms. See [`LICENSE`](LICENSE).

Upstream project: <https://github.com/hugen79/NanoVNA-H>
Pinned release: `1.2.50` (`816495ebc8ca022149787ec2f9e058d6ce3bcb3b`).
