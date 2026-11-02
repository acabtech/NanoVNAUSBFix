# Patches

All patches apply to the pinned upstream tag `1.2.50` with `patch -p1` from the
source root. `scripts/build.sh` applies them in this order.

| Patch | Applied to | Purpose |
| --- | --- | --- |
| `0001-usb-clock-pclk.patch` | both flavors | Select PCLK as the USB clock instead of HSI48. |
| `0002-usbtmc-scpi.patch` | unofficial only | Composite CDC + USBTMC interface and the SCPI bridge. |
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
