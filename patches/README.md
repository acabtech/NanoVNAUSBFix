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
