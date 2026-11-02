# Contributing

Thanks for helping make NanoVNA USB reliable.

## Ground rules

- Keep the upstream tree pristine. Changes belong in `patches/`, never in a
  committed copy of NanoVNA-H.
- One logical change per patch. Patches must apply with `patch -p1` to the
  pinned upstream tag.
- Do not add build outputs, `.bin`/`.hex`/`.elf` files, or the unpacked upstream
  tree to git.
- Preserve the official image. [`patches/0001-usb-clock-pclk.patch`](patches/0001-usb-clock-pclk.patch)
  is frozen unless there is a confirmed enumeration/USB bug with a reproduction
  and a hardware regression test. New features go in the unofficial patch
  series only.
- Test both flavors before opening a pull request:

```bash
make clean
make dist
```

## Patch series

Patches are cumulative and numbered in application order. Each patch must have
one purpose and must leave both flavors buildable when applied in sequence.

| Patch | Flavor | Purpose |
| --- | --- | --- |
| `0001-usb-clock-pclk.patch` | both | Frozen PCLK USB-clock fix |
| `0002-usbtmc-scpi.patch` | unofficial | Composite CDC + USBTMC and the SCPI bridge |
| `0003-usbtmc-shell-output.patch` | unofficial | Per-thread USBTMC shell output and byte-path capture; fixes the `:VNA:CMD?` hang and empty responses |

For v0.2.0 the unofficial series will be split into logical patches as
milestones land (transport, VNA parity, autoset, calibration, screenshot). Keep
[`patches/README.md`](patches/README.md) and
[`docs/architecture.md`](docs/architecture.md) in sync with the series.

## Adding a patch

```bash
make fetch
cd build/upstream
# edit, then create a diff against the pinned tree
diff -ruN ../upstream-orig . > ../../patches/0003-my-change.patch
```

Adjust paths so the patch applies from the source root with `patch -p1`, then
add it to the relevant `PATCHES` array in `scripts/build.sh` and document it in
`docs/`.

## Commit style

```
feat: add ...
fix: ...
docs: ...
build: ...
```

## Reporting issues

Include:

- firmware asset name and `SHA256SUMS` line;
- `lsusb -v` for `0483:5740` or `0483:df11`;
- `dmesg` around plug-in;
- exact command and response;
- whether the official PCLK image works on the same unit.

Security reports: see [`SECURITY.md`](SECURITY.md).
