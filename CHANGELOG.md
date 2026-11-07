# Changelog

All notable changes to this project are documented here. Firmware version
numbers track the upstream NanoVNA-H release; the project version tags are
independent (for example `v0.1.0` packaging upstream `1.2.50`).

## [Unreleased] — v0.2.0

The v0.2.0 milestone plan is in [`plans/milestones.md`](plans/milestones.md).
Work in progress; entries are added as milestones land.

### Added

- FLASH-1 calibration-slot reduction, applied to **both** flavors. Calibration
  config storage no longer reserves 32 KiB:
  - Official: `0014-flash1-reduce-cal-slots.patch` sets `SAVEAREA_MAX` to **2**
    and moves the F072 split to `flash0 114k` / `flash7 0x0801C800 + 14k`
    (2 KiB `config_t` + 2 × 6 KiB records). `0015-official-ui-two-slots.patch`
    gates the third save/recall menu entry on `SAVEAREA_MAX > 2`, so the UI
    offers exactly two profiles. The application region grows from 96 KiB to
    114 KiB; because the cal addresses are computed backwards from the end of
    flash, previously stored calibrations are invalidated.
  - Unofficial: `0016-flash1-unofficial-three-records.patch` keeps RAM-6's
    ping-pong working/scratch records and adds a **single** user-visible profile
    (`CAL_USER_SLOTS` 3 → **1**), for `SAVEAREA_MAX` **3** and a 20 KiB
    reservation (`flash0 108k`, `flash7 0x0801B000 + 20k`). The shell
    `save`/`recall` bounds, UI menus and the backup-slot check all follow
    `CAL_USER_SLOTS`. A 2-slot in-place design (one profile plus one working
    record with a 2 KiB page-staging buffer) was rejected: see
    [`docs/architecture.md`](docs/architecture.md) for why `cal_done()` cannot
    compute the error terms in place.
  Free RAM is unchanged for the unofficial flavor at **4,776 B** (the ping-pong
  records stay on flash); official RAM is unchanged.
- Fixed three RAM-6 calibration defects in
  `0016-flash1-unofficial-three-records.patch`, all found by testing on hardware:
  `cal_record_valid()` read the checksum from `properties_t.checksum` (offset
  208, the first calibration value in the flash record) instead of
  `PROPS_CHECKSUM_OFFSET`, so no saved record validated and `recall` always fell
  back to defaults; `caldata_recall()` did not reload the saved header before
  rebuilding the working record, so sweep/trace settings were never restored;
  and the `save`/`recall` usage messages passed `%s` and `%d` in the wrong
  order, printing `(null) 0..134292061`. Verified on hardware: sweep round-trip,
  a full calibration surviving `save` -> `cal reset` -> `recall`, and
  persistence across a reboot.
- RAM-6 flash-backed calibration (`0013-ram6-flash-backed-cal-data.patch`):
  the 4,040-byte `_cal_data` array no longer lives in RAM. It is read from a
  pair of ping-pong flash calibration records through a `cal_data` pointer, and
  `cal_collect()` / `cal_done()` rebuild the live record into the spare slot one
  point at a time, so no 4 KB staging buffer is required. `properties_t` shrinks
  from 4,252 to 212 bytes and free RAM rises from 820 to **4,776 B**
  (`_bss_end` `0x20003ccc` -> `0x20002d58`). The two highest flash slots are now
  the working/scratch pair, so **user-visible calibration slots drop from 5 to
  3**; the shell `save`/`recall` range, the UI menus and the backup-slot bound
  all use `CAL_USER_SLOTS`. The on-flash and SD `.cal` record layout is
  byte-for-byte the upstream `properties_t` image, so calibrations remain
  interchangeable with the official firmware.
- RAM-8 headless mode (`0012-ram8-headless.patch`): `headless on|off` skips
  `ui_process()`, the trace-index cache and cell rendering, paints a notice
  screen, and blinks the green LED at 1 Hz. It is also reachable from
  `CONFIG -> CONNECTION -> HEADLESS MODE`. With a continuous 101-point sweep
  the sweep-thread loop period measured **568 ms in normal mode and 385 ms in
  headless** (1.48x throughput) on hardware. The render caches now live in a
  union with a reusable scratch arena (`plot_headless_scratch()`); `_bss_end`
  is unchanged at `0x20003ccc`. The mode is runtime-only and deliberately not
  persisted, so a power cycle restores the display.
- Binary measurement transfer (M2, `0005-m2-binary-data-transfer.patch`):
  `:VNA:DATA:BLOCK?` returns a full or windowed sweep as an IEEE-488.2
  definite-length block of 12-byte points (`uint32` Hz, `float32` re, `float32`
  im, little-endian), and `:VNA:DATA:CHUNK?` accepts a trailing `BIN`/`BLOCK`
  argument. A 101-point sweep is one 1,218-byte response.
- `:VNA:DATA:PRE?` returns a waveform-style preamble
  (`points,start_hz,step_hz,RI32,12`).
- RAM-0 process safeguards: `scripts/verify.sh` now reads `_bss_end` and
  `__ram0_end__` from each ELF, warns below 1 KiB free and fails below 200 B
  (`RAM_ALLOW_LOW=1` is a one-off local override). `patches/0006` adds a
  `stack` shell command that reports high-water usage for the `sweep` and
  `main` stacks without enabling `CH_CFG_USE_REGISTRY`.
- Non-USB recovery tooling:
  [`scripts/recover-openocd.sh`](scripts/recover-openocd.sh) flashes over
  ST-Link/SWD with OpenOCD, and
  [`scripts/recover-uart.sh`](scripts/recover-uart.sh) uses the STM32 ROM UART
  bootloader. Both accept either image, install missing packages, can install
  the pinned toolchain and the NanoVNA + ST-Link udev rules, and are documented
  in [`docs/debugging.md`](docs/debugging.md).
- The unofficial flavor is back on `-O2`
  (`0017-unofficial-build-o2.patch`). `0005` had switched it to `-Os` because the
  old 96 KiB code region was full at `-O2` (97,910 of 98,304 bytes, 394 free).
  FLASH-1 widened that region to 108 KiB, so the override is no longer needed:
  measured on the same tree, `-Os` gives 93,020 bytes and `-O2` 100,212 bytes,
  leaving 10,380 bytes of region free. RAM changes by 4 bytes (alignment), and
  the worst stack frame is unchanged (`cmd_dump`, 416 bytes). The official
  `-USB-PCLK` image is unchanged in size (91,648 bytes) and stays frozen.

### Changed

- Project identity bumped from `1.3.0-omariglol` to `1.3.1-omariglol` across
  `PROJECT_VERSION`, `USBFIX_RELEASE`, artifact filenames, scripts, docs and
  the issue/release templates.
- RAM-2: the unofficial flavor now uses a 704-byte `waThread1` working area
  (down from 1024) and a 0x240 process stack (up from 0x200). Measured on
  hardware: the sweep thread's worst case is 736 bytes including `thread_t`
  (136 bytes free, after `dump`), and the main boot path uses 460 bytes
  (116 bytes free). Net saving is 256 bytes; the official flavor stays on the
  0x200 process stack.
- RAM-3: the measurement module's `measure_memory` scratch buffer is now
  80 bytes (down from 128) and 4-byte aligned, with `_Static_assert`s guarding
  every structure that aliases it. This saves 48 bytes of RAM and 1,812 bytes
  of flash (GCC emits direct word accesses for the float views). `rx_buffer`
  is not a serial buffer; it is the 384-byte I2S DMA buffer and is unchanged.
- RAM-4: `trace_index` is now a `uint16_t` x array plus a `uint8_t` y array
  instead of a `uint16_t x/y` struct array. The cache holds already-clamped
  screen pixels, and `HEIGHT` is 232 on the 320x240 F072 panel, so y fits in
  8 bits (it widens automatically if `HEIGHT > 255`). Saves 504 bytes of RAM
  (free RAM 316 -> 820; `_bss_end` `0x20003ccc`), with no change to
  measurement data. A 50-frame redraw benchmark on hardware measured the same
  time before and after (~20,599 ticks per full frame).
- RAM-1: the unofficial flavor now builds with `FF_FS_TINY=1`
  (`patches/0007`). It was measured at **0 B** RAM saved, not the estimated
  ~512 B, because `FATFS` and `FIL` are overlaid in the fixed-size
  `spi_buffer`. The setting is retained as a prerequisite for a future
  `SPI_BUFFER_SIZE` reduction.
- Release assets are now versioned with the project identity rather than the
  pinned upstream version: `NanoVNA-H-1.3.1-omariglol-USB-PCLK.*` (previously
  `NanoVNA-H-1.2.50-USB-PCLK.*`) and `NanoVNA-H-1.3.1-omariglol.*` (previously
  `NanoVNA-H-1.2.50-USBTMC.*`). `scripts/build.sh` keeps the pinned upstream
  tarball version (`1.2.50`) separate from `PROJECT_VERSION`
  (`1.3.1-omariglol`), so patching and verification are unchanged.
- `*IDN?` reports `NanoVNA-H,USBFix,1.3.1-omariglol,<UID>`.

### Fixed

- Fixed the unofficial-image boot hang: `draw_cell()` clears `spi_buffer` with
  32-bit stores, but the unofficial BSS layout placed `spi_buffer` at a
  two-byte-aligned address. Cortex-M0 raises a HardFault on the unaligned
  `str`, leaving the USB device unable to answer enumeration. `patches/0008`
  forces `spi_buffer` to 4-byte alignment. The official image already landed on
  a 4-byte-aligned address and is unchanged.
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
