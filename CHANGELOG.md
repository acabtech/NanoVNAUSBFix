# Changelog

All notable changes to this project are documented here. Firmware version
numbers track the upstream NanoVNA-H release; the project version tags are
independent (for example `v0.1.0` packaging upstream `1.2.50`).

## [Unreleased] — v0.2.0

The v0.2.0 milestone plan is in [`plans/milestones.md`](plans/milestones.md).
Work in progress; entries are added as milestones land.

### Added

- Binary measurement transfer (M2, `0005-m2-binary-data-transfer.patch`):
  `:VNA:DATA:BLOCK?` returns a full or windowed sweep as an IEEE-488.2
  definite-length block of 12-byte points (`uint32` Hz, `float32` re, `float32`
  im, little-endian), and `:VNA:DATA:CHUNK?` accepts a trailing `BIN`/`BLOCK`
  argument. A 101-point sweep is one 1,218-byte response.
- `:VNA:DATA:PRE?` returns a waveform-style preamble
  (`points,start_hz,step_hz,RI32,12`).
- The unofficial flavor now builds with `-Os`. The F072 code region is 96 KiB
  and the `-O2` image had 394 bytes free, so further milestones could not link.
  Image size is 93,176 bytes, leaving about 5 KiB for M3/M5. The official
  `-USB-PCLK` image is unchanged in size (91,704 bytes) and still builds at
  `-O2`.

### Changed

- Release assets are now versioned with the project identity rather than the
  pinned upstream version: `NanoVNA-H-1.3.0-omariglol-USB-PCLK.*` (previously
  `NanoVNA-H-1.2.50-USB-PCLK.*`) and `NanoVNA-H-1.3.0-omariglol.*` (previously
  `NanoVNA-H-1.2.50-USBTMC.*`). `scripts/build.sh` keeps the pinned upstream
  tarball version (`1.2.50`) separate from `PROJECT_VERSION`
  (`1.3.0-omariglol`), so patching and verification are unchanged.
- `*IDN?` reports `NanoVNA-H,USBFix,1.3.0-omariglol,<UID>`.

### Fixed

- CI and release builds now run in an `archlinux:base-devel` container with the
  pinned GCC 16.2.0 / binutils 2.47 / newlib 4.6.0.20260123 toolchain. Ubuntu's
  `gcc-arm-none-eabi` 13.2.1 linked a 94,208-byte official image and failed the
  92,160-byte budget even though the pinned compiler produces the 91,704-byte
  baseline. The toolchain packages and upstream tarball are cached between runs.
- `:VNA:CMD?` no longer deadlocks the USBTMC stack. The shell output path is
  routed per-thread instead of swapping the global `shell_stream` while the CDC
  shell holds its mutex across a blocking read. This fixes the v0.1.0 hang where
  `:VNA:CMD? info` or `:VNA:CMD? version` wedged every later USB request until a
  power cycle.
- `:VNA:CMD?` now returns the captured shell output. ChibiOS `chvprintf()`
  writes through the single-byte `put` hook, which the USBTMC memory stream had
  left as a no-op.

## [0.1.0] - 2026-11-02

This is the current shipped baseline. It was originally written as `1.0.0`;
the project now treats that release as `v0.1.0`.

### Added

- Official firmware build: upstream NanoVNA-H 1.2.50 with the USB peripheral
  clocked from PCLK (`STM32_USBSW_PCLK`) instead of HSI48.
- Unofficial firmware build: the same clock fix plus a composite CDC + USBTMC
  interface exposing a SCPI command surface for omariglol's generic USB layer.
- `:VNA:` SCPI commands for sweep control, CW frequency, pause/resume, data
  reads and a full stock-shell escape hatch.
- Reproducible build script pinned to upstream tag `1.2.50` and tarball SHA-256.
- CI, release workflow, artifact verification and DFU flashing helper.
- Documentation: architecture, USB API, building, flashing, testing.

### Notes

- A CRS/HSI48 trimming experiment did not fix enumeration on the affected unit
  and is kept under `docs/experiments/` for reference only.
