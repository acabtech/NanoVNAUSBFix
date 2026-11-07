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
| `0011-ram4-trace-index.patch` | unofficial only | RAM-4: splits the per-trace screen-coordinate cache into a `uint16_t` x array and a `uint8_t` y array. `y` is clamped to `HEIGHT` and fits in 8 bits on the 320x240 F072 panel (it widens automatically if `HEIGHT > 255`). Saves 504 bytes of RAM with no change to measurement data or redraw speed. |
| `0012-ram8-headless.patch` | unofficial only | RAM-8: adds a runtime-only `headless on\|off` mode, also available from `CONFIG -> CONNECTION -> HEADLESS MODE`. Headless skips `ui_process()`, trace-cache generation and cell rendering, paints a 2x-titled "display disabled" notice, and blinks the green LED at 1 Hz. The ~1.5 KiB render cache is a union with a reusable scratch arena (`plot_headless_scratch()`); `_bss_end` is unchanged. Not persisted: a power cycle returns to the normal display. |
| `0013-ram6-flash-backed-cal-data.patch` | unofficial only | RAM-6: moves the 4,040-byte `_cal_data` array out of RAM and into a pair of ping-pong flash calibration records, reached through a `cal_data` pointer. `cal_collect()` and `cal_done()` rebuild the live record into the spare slot (point-wise for `cal_done()`), so no 4 KB staging buffer is needed. `properties_t` shrinks from 4,252 to 212 bytes and free RAM rises from 820 to **4,776 B** (`_bss_end` `0x20003ccc` → `0x20002d58`). The two highest flash slots become the working/scratch pair, so user slots drop from 5 to **3** (`CAL_USER_SLOTS`). The on-flash and SD `.cal` record layout is unchanged and stays compatible with the official firmware. |
| `0014-flash1-reduce-cal-slots.patch` | official only | FLASH-1 for the official flavor: `SAVEAREA_MAX` 5 → **2** and the F072 linker split changes from `flash0 96k` / `flash7 32k` to `flash0 114k` / `flash7 0x0801C800 + 14k`. The reservation becomes `0x800` config + 2 × `0x1800` records = **14 KiB**, returning 18 KiB to the code region. Calibration addresses are computed backwards from the end of flash, so existing official calibrations are invalidated (expected, documented in the plan). |
| `0015-official-ui-two-slots.patch` | official only | FLASH-1 UI follow-up: `menu_save` / `menu_recall` gate the third entry on `SAVEAREA_MAX > 2` instead of unconditionally listing slots 0–2, so the official UI shows exactly two calibration profiles. |
| `0016-flash1-unofficial-three-records.patch` | unofficial only | FLASH-1 for the unofficial flavor, preserving RAM-6's correctness model. Reduces user-visible slots from 3 to **1** (`CAL_USER_SLOTS` → 1, slots 1/2 stay the ping-pong working/scratch pair), sets `SAVEAREA_MAX` 5 → **3**, and retunes the F072 linker split to `flash0 108k` / `flash7 0x0801B000 + 20k` (`0x800` config + 3 × `0x1800` records = **20 KiB**). The transform stays ping-pong because a 2 KiB page-staging redesign cannot compute `cal_done()`'s error terms in place: every first-page erase destroys inputs needed by a later term, and the extra scratch would exceed the remaining ~2.8 KiB of RAM. Shell bounds, UI menus and backup-slot checks follow `CAL_USER_SLOTS`.

  Also fixes three bugs inherited from `0013` that made save/recall unusable on hardware: `cal_record_valid()` compared the record checksum against `properties_t.checksum` (offset 208, which in the flash record is the first calibration value) instead of the checksum stored at `PROPS_CHECKSUM_OFFSET`, so every record failed validation and `recall` always fell back to defaults; `caldata_recall()` copied only the calibration arrays and never restored the saved header, because `cal_record_write()` always programs the header from `current_props`, so sweep/trace settings were silently not restored; and the `save`/`recall` usage strings passed `%s` and `%d` arguments in the wrong order, printing `(null) 0..134292061`. Verified on hardware: `save 0` / `recall 0` round-trips the sweep, a full `cal load/open/short/thru/done` survives `save` -> `cal reset` -> `recall`, and the calibration persists across a reboot. Slots 1 and 2 are rejected by the shell (`id = 0..0`). |
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
