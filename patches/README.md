# Patches

All patches apply to the pinned upstream tag `1.2.50` with `patch -p1` from the
source root. `scripts/build.sh` applies them in this order.

## Conventions

- One logical change per patch; the patch must leave its flavor buildable.
- Patches are cumulative and numbered in application order.
- `0001-usb-clock-pclk.patch` is frozen. It may only change for a confirmed
  USB bug with a reproduction and a hardware regression test.
- Every new feature targets the unofficial flavor. Do not add features to the
  official patch set or to the official build flags.
- Update this table, [`docs/architecture.md`](../docs/architecture.md) and
  [`docs/usb-api.md`](../docs/usb-api.md) in the same change as the patch.
- For v0.2.0, split the unofficial series as milestones land: transport
  hardening, VNA parity, autoset, calibration and screenshot export.

| Patch | Applied to | Purpose |
| --- | --- | --- |
| `0001-usb-clock-pclk.patch` | both flavors | Select PCLK as the USB clock instead of HSI48. Frozen. |
| `0002-usbtmc-scpi.patch` | unofficial only | Composite CDC + USBTMC interface and the SCPI bridge. |
| `0003-usbtmc-shell-output.patch` | unofficial only | Route USBTMC shell output per-thread and buffer the `chvprintf()` byte path. Fixes the `:VNA:CMD?` hang and empty responses. |
| `0004-scpi-foundation-sweep-parity.patch` | unofficial only | M1 SCPI foundation (error queue, `:SYST:*`, UID serial, abort) and M2 sweep/acquisition parity (center/span, single/continuous, status, averaging, IFBW, power, telemetry). Authored by acabtech and @brrrassica. |
| `0005-m2-binary-data-transfer.patch` | unofficial only | M2 binary measurement transfer: IEEE-488.2 definite-length blocks (`:VNA:DATA:BLOCK?`, `:VNA:DATA:CHUNK? ...,BIN`) and the `:VNA:DATA:PRE?` preamble. Also reports the `1.3.1-omariglol` release identity in `*IDN?` and builds the unofficial flavor with `-Os` to fit the 96 KiB code region. |
| `0006-ram0-stack-command.patch` | unofficial only | Adds the `stack` shell command, which reports high-water stack usage for the sweep and main threads by scanning the ChibiOS fill pattern. No thread registry is required, so it does not add RAM. |
| `0007-ram1-ff-fs-tiny.patch` | unofficial only | Sets `FF_FS_TINY=1` in `FatFs/ffconf_072.h`. Measured saving is 0 B while FatFs stays overlaid in `spi_buffer`; kept as a prerequisite for a future `SPI_BUFFER_SIZE` reduction. |
| `0008-fix-spi-buffer-alignment.patch` | unofficial only | Forces 4-byte alignment of `spi_buffer`. The LCD cell-clear code writes it as `uint32_t`, and the unofficial BSS layout placed it at a 2-byte-aligned address, causing an unaligned store HardFault before USB could enumerate. |
| `0009-ram2-stack-sizes.patch` | unofficial only | RAM-2: shrinks `waThread1` from 1024 to 704 bytes (measured worst case 736 bytes including `thread_t`, leaving 136 bytes) and raises the unofficial process stack from 0x200 to 0x240 (main boot-path high-water 460 bytes, leaving 116). The Makefile gates the larger process stack on `USBTMC=yes`, so the official flavor is unchanged. |
| `0010-ram3-measure-memory.patch` | unofficial only | RAM-3: shrinks the measurement module's shared scratch buffer from 128 to 80 bytes, forces 4-byte alignment, and adds `_Static_assert`s for every structure aliasing it. Saves 48 bytes of RAM and 1,812 bytes of flash; `rx_buffer` is intentionally left alone because it is the I2S DMA buffer. |
| `optional-rtc-default-time.patch` | not applied | Seed an uninitialised RTC to 2026-11-01 00:00:00. |

## Regenerating a patch

```bash
make clean
make fetch
cd build/upstream
# edit ...
diff -ruN ../upstream-orig . > ../../patches/0003-change.patch
```

Normalise the paths to `a/...` and `b/...` so `patch -p1` works. Do not commit
the unpacked tree.
