# Contributing

Thanks for helping make NanoVNA USB reliable.

## Ground rules

- Keep the upstream tree pristine. Changes belong in `patches/`, never in a
  committed copy of NanoVNA-H.
- One logical change per patch. Patches must apply with `patch -p1` to the
  pinned upstream tag.
- Do not add build outputs, `.bin`/`.hex`/`.elf` files, or the unpacked upstream
  tree to git.
- Test both flavors before opening a pull request:

```bash
make clean
make dist
```

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
