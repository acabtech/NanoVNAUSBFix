# Changelog

All notable changes to this project are documented here. Firmware version
numbers track the upstream NanoVNA-H release; the project version tags are
independent (for example `v0.1.0` packaging upstream `1.2.50`).

## [Unreleased] — v0.2.0

The v0.2.0 milestone plan is in [`plans/milestones.md`](plans/milestones.md).
Work in progress; entries are added as milestones land.

### Fixed

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
