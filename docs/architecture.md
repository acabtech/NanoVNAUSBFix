# Architecture

## Two flavors, one pinned base

```text
upstream NanoVNA-H 1.2.50
        │
        ├── 0001-usb-clock-pclk.patch
        │       └── official firmware (CDC shell only)
        │
        └── 0001 + 0002 + 0003 + 0004
                └── unofficial firmware (CDC + USBTMC/SCPI)
```

Everything in `patches/` applies to a freshly unpacked upstream tarball with
`patch -p1`. The build script never edits the repository tree.

## Clock path

The STM32F072 has a USB clock mux (`RCC_CFGR3.USBSW`) with two practical
sources:

| Source | Accuracy | Notes |
| --- | --- | --- |
| HSI48 | nominal 48 MHz, can be trimmed by CRS from USB SOF | upstream default; failed to enumerate on the affected unit |
| PCLK | the 48 MHz system PLL output | the fix; CPU and USB share the same PLL |

The affected unit asserted D+ but never completed control transfers when the
core was clocked from HSI48. The ROM DFU bootloader worked, which ruled out the
PHY and wiring. With PCLK selected, the same board enumerates as a CDC ACM
device immediately.

The project does **not** enable CRS. There is no HSI48 trim loop to tune, and no
dependency on SOF reception for the clock to be valid. That is the point of the
fix.

## USB composite device (unofficial build)

The unofficial image keeps the stock CDC ACM function and adds a USBTMC
interface:

```text
Configuration 1
├── Interface 0  CDC Communication (class 0x02, subclass 0x02)
│   └── EP2 IN interrupt
├── Interface 1  CDC Data (class 0x0A)
│   ├── EP1 OUT bulk
│   └── EP1 IN  bulk
└── Interface 2  USBTMC (class 0xFE, subclass 0x03, protocol 0x01)
    ├── EP3 OUT bulk
    ├── EP3 IN  bulk
    └── EP4 IN  interrupt
```

The device descriptor advertises class `0x00` (class defined per interface), so
Linux binds `cdc_acm` to interfaces 0/1 and `usbtmc` (or omariglol's libusb
path) to interface 2.

### USBTMC handling

USBTMC bulk messages have a 12-byte header followed by a payload. The firmware
implements the subset a host needs for SCPI request/response:

- `DEV_DEP_MSG_OUT` (1) — command bytes from host to device.
- `REQUEST_DEV_DEP_MSG_IN` (2) — host asks for the next response chunk.
- `EOM` transfer attribute — marks the end of a command.
- Class control requests: `READ_STATUS_BYTE`, `INITIATE_CLEAR`,
  `CHECK_CLEAR_STATUS`, `GET_CAPABILITIES`, and the abort requests.

The interrupt path only frames bytes and queues one command. Command execution
happens in the sweep thread between sweeps. That keeps VNA state access out of
interrupt context and lets `:VNA:SWE:EXEC` perform a real measurement.

### Shell output routing

The stock shell writes through one global `shell_stream`. v0.1.0 temporarily
swapped that pointer while running a `:VNA:CMD?` command and held a mutex across
the swap. The CDC shell holds that mutex while blocking on input, so a USB shell
command deadlocked the sweep thread and every later USBTMC request timed out.

The unofficial firmware now routes `shell_printf` by thread: while the sweep
thread runs a captured command, only that thread writes to the USBTMC response
stream. CDC echo and output keep using the normal shell stream. No mutex is held
across the blocking read.

The memory stream must implement both the bulk `write` and single-byte `put`
hooks: ChibiOS `chvprintf()` emits format output through `streamPut()`.
v0.1.0 left `put` as a no-op, so even after the deadlock was removed the escape
hatch returned an empty response.

### Response storage

The F072 has 16 KiB of RAM and the stock firmware already uses almost all of it.
To avoid a second large static buffer, USBTMC responses borrow `spi_buffer`, the
LCD scratch buffer. Drawing is paused while a response is pending
(`usbtmc_response_pending()`), and resumes once the host has read the EOM chunk.
The result is zero static RAM growth for the response path; the trade-off is
that a host which stops reading can briefly freeze the display.

### Binary measurement transfer

`vna_usb_data_block()` encodes a window of `measured[][]` straight into the
response buffer as an IEEE-488.2 definite-length block. Each point is 12 bytes
(`uint32` Hz, `float32` re, `float32` im) so a 101-point sweep is 1,212 bytes
plus a six-byte `#`/length header, which fits in one bulk-IN transfer. No second
sweep buffer is allocated; the encoder reads the existing measurement arrays.

### Flash budget and optimisation level

Since FLASH-1 the linker script gives the application **114 KiB** of the F072's
128 KiB flash for the official flavor (`108 KiB` for the unofficial one); the
remainder (`flash7`) is reserved for configuration and calibration storage — 14
KiB official, 20 KiB unofficial.

Both flavors now build at `-O2`. The unofficial flavor had been switched to
`-Os` by `0005-m2-binary-data-transfer.patch` because the old 96 KiB code
region was full at `-O2` (the image was 97,910 of 98,304 bytes, 394 bytes free).
FLASH-1 widened that region to 108 KiB, and
`0017-unofficial-build-o2.patch` drops the `-Os` override. Measured with the
same source tree:

| Optimisation | `.bin` size | Free in `flash0` | Free RAM |
| --- | ---: | ---: | ---: |
| `-Os` | 93,020 B | 17,572 B | 4,776 B |
| `-O2` | 100,212 B | 10,380 B | 4,772 B |

So `-O2` costs 7,192 bytes of flash and 4 bytes of RAM (alignment padding) and
still leaves 10 KiB of region free. The official flavor keeps `-O2` and its
frozen size (91,648 B of a 92,160 B budget; it does not draw on the 18 KiB
FLASH-1 gave back, so the frozen-baseline rule still holds).

Stack usage was re-checked at `-O2` from the `-fstack-usage` output: the worst
single frame is still `cmd_dump` at 416 bytes, which is the case already
measured on hardware (736 B including `thread_t`, 136 B margin in the 704-byte
`sweep` thread). Sweep timing should be re-measured on hardware with
`:VNA:SWE:TIME?` and `:VNA:SWE:RATE?` before release, since `-O2` changes the
generated code.

### Calibration storage (RAM-6)

The 4,040-byte calibration array (`_cal_data`) is kept on flash, not in RAM.
`properties_t` now holds only the 208-byte mutable header plus a checksum, and
`cal_data` is a pointer into the live flash record. The two highest calibration
slots form a ping-pong pair: the live record occupies one, the other is the
erase target for the next write. `cal_collect()` adds one collected array and
`cal_done()` derives Es/Er/Et point by point, each time rebuilding the record in
the spare slot and swapping. This needs no RAM staging because the source record
is only ever read while the destination is erased and programmed. The record
layout is byte-identical to the upstream `properties_t` image, so flash slots
and SD `.cal` files stay compatible with the official firmware.

FLASH-1 (`0016-flash1-unofficial-three-records.patch`) cuts the number of
user-visible profiles. The unofficial flavor keeps the ping-pong working/scratch
pair and adds a **single** saved profile in slot 0 (`CAL_USER_SLOTS` = 1), for a
3-record / 20 KiB reservation. The official flavor uses two plain profiles
(`SAVEAREA_MAX` = 2) and a 14 KiB reservation via
`0014-flash1-reduce-cal-slots.patch` and `0015-official-ui-two-slots.patch`.

Save/recall had three defects introduced with RAM-6 and fixed in
`0016-flash1-unofficial-three-records.patch`: record validation read the
checksum from the wrong offset (so no saved record was ever accepted), recall
did not reload the saved header (so only the calibration arrays were restored,
not the sweep), and the shell usage strings had swapped `printf` arguments. All
three are verified on hardware.

A two-record in-place design (one user profile plus one working record, edited
through a 2 KiB page-staging buffer) was prototyped and rejected: `cal_done()`
must read all five 808-byte error-term arrays to derive Es/Er/Et, and those
arrays straddle all three record pages. Erasing any page first destroys source
values needed by a later term, so in-place derivation is impossible without
about 5 KiB of scratch — more than the free RAM after RAM-6. Ping-pong remains
the only layout that fits in the available RAM and flash.

### SCPI state without extra BSS

The v0.1.0 link left no free BSS: `_bss_end` was already at the end of RAM, so
even a few new bytes failed to link. RAM-2/RAM-3/RAM-4 now leave 820 bytes free
(`_bss_end` `0x20003ccc`), but the M1/M2 command state still lives in
`properties_t._reserved1[]`, which upstream does not use, so it does not
compete with future RAM work:

- averaging depth and restart flag;
- last sweep duration and point count;
- a packed eight-entry error queue (4-bit codes) with head and count.

`vna_host_state_init()` clears those words after every property/calibration
recall, so values copied from flash can never leak into host state. Trace
averaging itself is computed in place over `measured[][]` as an exponential
moving average, which also avoids a second sweep buffer.

One consequence: `:VNA:CMD? capture` is not supported, because the screenshot
command also uses `spi_buffer` internally. Use the CDC interface for screenshots
and SD-card commands.

## Headless mode (RAM-8)

The display can be turned off at runtime with the unofficial `headless on`
shell command or from the screen at `CONFIG -> CONNECTION -> HEADLESS MODE`.
Headless is not stored in `config`, so a power cycle always restores the normal
display even if the USB link is unavailable.

When headless is active the sweep thread no longer calls `ui_process()` or
`draw_all()`: the trace-index cache, the markmap and cell rendering are all
skipped. A one-time 240x320 notice is painted and the green LED blinks at
1 Hz. On hardware, a continuous 101-point sweep loop measured 568 ms per
iteration in normal mode and 385 ms headless; the ~183 ms difference is the
measured full-frame render cost.

The render-only caches (`trace_index_x`, `trace_index_y`, `markmap`, 1,532 B
total) are a `union` with a scratch arena. `plot_headless_scratch()` returns
the arena only while headless. Because the mode is runtime-only, `_bss_end`
does not change; the memory is reused rather than removed from the image.

## omariglol integration

`omariglol-core` already has:

- a backend-agnostic USB device model (`UsbId`, `UsbSelector`,
  `UsbDeviceInfo`, enumeration);
- a USBTMC transport implementing `ScpiTransport`;
- a `usb:0xVVVV:0xPPPP[:SERIAL|BUS.ADDR]` address form.

The unofficial firmware does not add a new protocol driver to omariglol. It
presents a USBTMC instrument that the existing generic layer can enumerate and
open. The VNA-specific command surface lives in the SCPI strings documented in
[`usb-api.md`](usb-api.md).
