# USB API (unofficial USBTMC build)

The unofficial firmware enumerates a **USBTMC** interface alongside the normal
CDC ACM port. Any USBTMC-capable SCPI client can use it; the examples below use
omariglol's `riglol` CLI because it already implements the generic USB layer.

```bash
riglol usb list
riglol scpi --usb usb:0x0483:0x5740 '*IDN?'
```

VID/PID are unchanged from stock (`0483:5740`). The transport is selected by the
USBTMC interface class (`0xFE`/`0x03`), not by a different product ID.

## Framing

- Bulk OUT: 12-byte `DEV_DEP_MSG_OUT` header + command bytes.
- Bulk IN: 12-byte `DEV_DEP_MSG_IN` header + response bytes.
- Commands are newline-terminated by the client; the firmware also accepts a
  message whose `EOM` bit is set without a trailing newline.
- Responses are ASCII unless stated otherwise, terminated with `\r\n`.
- Maximum response is 4,084 bytes (the LCD scratch buffer). Use
  `:VNA:DATA:CHUNK?` for larger data sets.

## Common commands

| Command | Response | Notes |
| --- | --- | --- |
| `*IDN?` | `NanoVNA-H,USBFix,1.3.0-omariglol,<24 hex UID>` | SCPI identification; serial comes from the MCU UID |
| `*OPC?` | `1` | commands run in the sweep thread between sweeps, so the previous measurement is complete when this executes |
| `*CLS` | — | clears the SCPI error queue |
| `*RST` | — | clears the error queue, disables averaging and resumes continuous sweep |
| `:SYST:VERS?` | `1999.0` | SCPI version |
| `:SYST:ERR?` | `code,"description"` | pops one entry from the error queue |
| `:SYST:ERR:COUN?` | integer | number of queued errors |
| `:SYST:BEEP` | — | accepted for SCPI parity; the F072 NanoVNA-H has no beeper |
| `:SYST:BUILD?` | date/time string | firmware build timestamp |
| `:SYST:SER?` | 24 hex digits | MCU unique ID |

The error queue holds up to eight entries and uses standard SCPI codes:
`-113` undefined header, `-109` missing parameter, `-222` data out of range
and `-200` execution error. `:SYST:ERR?` returns `0,"No error"` when the queue
is empty.

## Sweep control

| Command | Response | Notes |
| --- | --- | --- |
| `:VNA:SWE:START <Hz>` | — | set sweep start |
| `:VNA:SWE:STOP <Hz>` | — | set sweep stop |
| `:VNA:SWE:CENT <Hz>` | — | set sweep center |
| `:VNA:SWE:SPAN <Hz>` | — | set sweep span |
| `:VNA:SWE:POINTS <n>` | — | set point count; out-of-range values return `-222` |
| `:VNA:SWE:START?` | integer Hz | current start |
| `:VNA:SWE:STOP?` | integer Hz | current stop |
| `:VNA:SWE:CENT?` | integer Hz | current center |
| `:VNA:SWE:SPAN?` | integer Hz | current span |
| `:VNA:SWE:POINTS?` | integer | current point count (`SWEEP_POINTS_MAX`, 101 on F072) |
| `:VNA:SWE:EXEC` | — | run one sweep using the current start/stop/points |
| `:VNA:SWE:SINGL` | — | pause and run exactly one sweep |
| `:VNA:SWE:CONT` | — | resume continuous sweep |
| `:VNA:SWE:PAUS` | — | pause the sweep |
| `:VNA:SWE:RES` | — | resume the sweep |
| `:VNA:SWE:ABOR` | — | cancel a pending single sweep and reset averaging |
| `:VNA:SWE:STAT?` | `RUN` or `PAUSE` | sweep state |
| `:VNA:SWE:TIME?` | integer ms | duration of the last completed sweep |
| `:VNA:SWE:RATE?` | integer | points per second from the last completed sweep |

`:VNA:SWE:EXEC` is synchronous from the host's point of view: the response to
the next query is sent after the sweep has completed. Sweep state commands do
not depend on the device UI.

## Acquisition controls

| Command | Response | Notes |
| --- | --- | --- |
| `:VNA:POW <0-3>` | — | set output drive strength; other values return `-222` |
| `:VNA:POW?` | integer | current output power setting |
| `:VNA:BAND <Hz>` | — | set IF bandwidth by frequency |
| `:VNA:BAND?` | integer Hz | current IF bandwidth |
| `:VNA:AVER ON\|OFF` | — | enable averaging (defaults to 4) or disable it |
| `:VNA:AVER:STAT <ON\|OFF>` | — | same as `:VNA:AVER` |
| `:VNA:AVER:STAT?` | `0` or `1` | averaging enabled |
| `:VNA:AVER:COUN <1-255>` | — | set averaging depth; out-of-range returns `-222` |
| `:VNA:AVER:COUN?` | integer | current averaging depth |
| `:VNA:AVER:RES` | — | restart the running average |
| `:VNA:TRIG:MODE <CONT\|STOP\|SINGL>` | — | continuous, stopped, or single sweep |
| `:VNA:TRIG:MODE?` | `CONT` or `STOP` | current trigger mode |
| `:VNA:TRIG:STAT?` | `RUN` or `IDLE` | sweep activity |

Averaging is an exponential moving average computed in place over the
measurement buffer, so it costs no additional RAM. The first sweep after
enabling averaging, changing the depth, or `:VNA:AVER:RES` starts fresh.

## Single frequency / continuous wave

| Command | Response | Notes |
| --- | --- | --- |
| `:VNA:FREQ <Hz>` | — | pause and tune to one frequency |
| `:VNA:FREQ?` | integer Hz | current CW frequency |
| `:VNA:PAUSE` | — | pause the continuous sweep |
| `:VNA:RESUME` | — | resume the continuous sweep |

## Measurement data

| Command | Response | Notes |
| --- | --- | --- |
| `:VNA:DATA? [ch]` | lines of `freq,re,im` | first chunk that fits; `ch` is 0 (S11) or 1 (S21) |
| `:VNA:DATA:CHUNK? <ch>,<start>,<count>[,BIN]` | lines of `freq,re,im`, or an IEEE-488.2 block with `BIN`/`BLOCK` | windowed read |
| `:VNA:DATA:BLOCK? [ch[,start[,count]]]` | IEEE-488.2 definite-length block | binary read; defaults to the whole sweep |
| `:VNA:DATA:PRE?` | `points,start_hz,step_hz,RI32,12` | waveform-style preamble for a binary read |

### Binary block layout

`:VNA:DATA:BLOCK?` and `:VNA:DATA:CHUNK? ... ,BIN` return a single USBTMC
response shaped as an IEEE-488.2 definite-length block:

```text
# <n> <length> <payload>
```

`<n>` is one decimal digit holding the number of digits in `<length>`, and
`<length>` is the decimal payload size in bytes. A 101-point payload of 1,212
bytes is therefore prefixed with `#41212`. Example — read a full S11 sweep in
one transfer (the bytes after the block header are binary):

```text
:VNA:DATA:PRE?            -> 101,1000000,290000,RI32,12
:VNA:DATA:BLOCK? 0        -> #41212<1212 bytes>
```

Every point is 12 bytes, little-endian (the Cortex-M0 is little-endian only):

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | `uint32` | frequency in Hz |
| 4 | `float32` | real part (S11 or S21, calibration applied) |
| 8 | `float32` | imaginary part |

The firmware clamps a binary read to the points that fit in the 4,084-byte
response window and reports the truncation through the block length, so a host
must reassemble large requests with `start`/`count` windows. The payload is not
newline- or NUL-terminated; rely on the block length only.

ASCII reads are unchanged and remain the compatibility path:

Example — read the first 16 S11 points:

```bash
riglol scpi --usb usb:0x0483:0x5740 ':VNA:DATA:CHUNK? 0,0,16'
```

```
1000000,0.998321,-0.012340
...
```

Read a 101-point sweep in four chunks:

```bash
for start in 0 32 64 96; do
  riglol scpi --usb usb:0x0483:0x5740 ":VNA:DATA:CHUNK? 0,${start},32"
done
```

## Full stock command set

Anything the stock shell can do is still reachable:

| Command | Response | Notes |
| --- | --- | --- |
| `:VNA:CMD <command>` | — | execute a stock shell command, discard output |
| `:VNA:CMD? <command>` | shell output | execute and capture up to the response limit |

Examples:

```bash
riglol scpi --usb usb:0x0483:0x5740 ':VNA:CMD? info'
riglol scpi --usb usb:0x0483:0x5740 ':VNA:CMD? version'
riglol scpi --usb usb:0x0483:0x5740 ':VNA:CMD? data 0'
riglol scpi --usb usb:0x0483:0x5740 ':VNA:CMD scan 1000000 30000000 101 0'
riglol scpi --usb usb:0x0483:0x5740 ':VNA:CMD saveconfig'
```

The stock command list includes `scan`, `data`, `frequencies`, `sweep`, `freq`,
`power`, `bandwidth`, `cal`, `save`, `recall`, `trace`, `marker`, `edelay`,
`s21offset`, `measure`, `smooth`, `config`, `threshold`, `transform`, `time`,
`vbat`, `tcxo`, and the SD-card commands when enabled by the upstream build.

> `:VNA:CMD? capture` is not supported: the screenshot command and the USBTMC
> response share `spi_buffer`. Use the CDC interface for screenshots.

## Error responses

Unsupported or malformed commands return a SCPI-style error string and push
the same code onto the error queue:

```
-113,"Undefined header"
-109,"Missing parameter"
-222,"Data out of range"
```

The queue is read with `:SYST:ERR?` and cleared by `*CLS`. Malformed commands
never wedge the transport; every path returns a parseable response.

## Client notes

- omariglol's `UsbTmcTransport` sends a command and then a
  `REQUEST_DEV_DEP_MSG_IN`; the firmware holds the request until the command
  has executed, so a slow sweep does not produce an empty response.
- The USBTMC interface also has an interrupt-IN endpoint, but no status
  notifications are generated. omariglol's transport does not require them.
- The CDC ACM interface remains available at the same VID/PID. If your tool
  opens `/dev/ttyACM*`, it is talking to the stock shell, not to USBTMC.
