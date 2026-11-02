# Architecture

## Two flavors, one pinned base

```text
upstream NanoVNA-H 1.2.50
        │
        ├── 0001-usb-clock-pclk.patch
        │       └── official firmware (CDC shell only)
        │
        └── 0001 + 0002-usbtmc-scpi.patch
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

One consequence: `:VNA:CMD? capture` is not supported, because the screenshot
command also uses `spi_buffer` internally. Use the CDC interface for screenshots
and SD-card commands.

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
