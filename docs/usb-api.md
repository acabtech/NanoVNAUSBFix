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
| `*IDN?` | `NanoVNA-H,USBFix,1.2.50,00000000` | SCPI identification |
| `*OPC?` | `1` | always complete |
| `*CLS` | — | clears nothing; accepted for compatibility |
| `*RST` | — | accepted; does not reset the VNA |
| `:SYST:ERR?` | `0,"No error"` | no error queue is maintained |

## Sweep control

| Command | Response | Notes |
| --- | --- | --- |
| `:VNA:SWE:START <Hz>` | — | set sweep start |
| `:VNA:SWE:STOP <Hz>` | — | set sweep stop |
| `:VNA:SWE:POINTS <n>` | — | set point count (up to `SWEEP_POINTS_MAX`, 101 on F072) |
| `:VNA:SWE:START?` | integer Hz | current start |
| `:VNA:SWE:STOP?` | integer Hz | current stop |
| `:VNA:SWE:POINTS?` | integer | current point count |
| `:VNA:SWE:EXEC` | — | run one sweep using the current start/stop/points |

`:VNA:SWE:EXEC` is synchronous from the host's point of view: the response to
the next query is sent after the sweep has completed.

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
| `:VNA:DATA:CHUNK? <ch>,<start>,<count>` | lines of `freq,re,im` | windowed read; use this for full sweeps |

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

Unsupported or malformed commands return a SCPI-style error string:

```
-113,"Undefined header"
-109,"Missing parameter"
```

## Client notes

- omariglol's `UsbTmcTransport` sends a command and then a
  `REQUEST_DEV_DEP_MSG_IN`; the firmware holds the request until the command
  has executed, so a slow sweep does not produce an empty response.
- The USBTMC interface also has an interrupt-IN endpoint, but no status
  notifications are generated. omariglol's transport does not require them.
- The CDC ACM interface remains available at the same VID/PID. If your tool
  opens `/dev/ttyACM*`, it is talking to the stock shell, not to USBTMC.
