# Building

## Toolchain

| Tool | Tested version | Package |
| --- | --- | --- |
| `arm-none-eabi-gcc` | 16.2.0 | `arm-none-eabi-gcc` (Arch), `gcc-arm-none-eabi` (Debian/Ubuntu) |
| GNU make | 4.4.1 | `make` / `base-devel` |
| `7z` | p7zip 17+ | `p7zip` / `p7zip-full` |
| `patch`, `curl`, `tar` | any recent | base system |

The upstream F072 build needs the **32-bit ARM bare-metal** toolchain, not the
host compiler. The firmware uses `-std=c11` and builds with the GCC version
pinned in CI.

## Commands

```bash
make official      # stock + PCLK fix, output in dist/official/
make unofficial    # stock + PCLK + USBTMC, output in dist/unofficial/
make dist          # both, then run scripts/verify.sh
make clean
```

`scripts/build.sh` performs these steps for one flavor:

1. Download `NanoVNA-H-1.2.50.tar.gz` into `build/cache/` if missing.
2. Verify it against the pinned SHA-256.
3. Unpack into `build/work/<flavor>/`.
4. Extract the bundled `ChibiOS.7z`.
5. Apply the flavor's patches with `patch -p1`.
6. Run `make clean TARGET=F072` and `make TARGET=F072 [USBTMC=yes]`.
7. Copy `H.bin`, `H.hex`, `H.elf` and `H.map` into `dist/<flavor>/` and write
   `SHA256SUMS`.

The repository working tree is not modified.

## Pinned upstream

| Item | Value |
| --- | --- |
| Repository | <https://github.com/hugen79/NanoVNA-H> |
| Tag | `1.2.50` |
| Commit | `816495ebc8ca022149787ec2f9e058d6ce3bcb3b` |
| Tarball SHA-256 | `3db755b50c84e9c426957882ea9c0c5506febc1310c179a680a1fef9918389ee` |

To inspect the tree without building:

```bash
make fetch
$EDITOR build/upstream/main.c
```

To develop a new patch, edit `build/upstream`, then generate a diff relative to
the pinned tree and add it to `patches/`. Do not commit the upstream tree.

## Artifact names

```text
dist/official/NanoVNA-H-1.2.50-USB-PCLK.{bin,hex,elf,map}
dist/unofficial/NanoVNA-H-1.2.50-USBTMC.{bin,hex,elf,map}
```

Both images are for `TARGET=F072` only.

## Optional patches

`patches/optional-rtc-default-time.patch` seeds the RTC to 2026-11-01 00:00:00
when the calendar has never been initialised. It is not applied by default; add
it to the `PATCHES` array in `scripts/build.sh` if you want it.

## CI

`.github/workflows/ci.yml` builds both flavors on every push and pull request.
`.github/workflows/release.yml` builds them on a `v*` tag and publishes the
artifacts with `SHA256SUMS`.
