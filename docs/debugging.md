# Recovery, debugging and profiling

This page covers the two non-USB recovery paths and the tools used to inspect
RAM and stack usage. Both firmware flavors (`official` and `unofficial`) use the
same STM32F072 and the same image address, `0x08000000`.

## ST-Link / OpenOCD rescue

Use this when USB/DFU does not enumerate, or when you want breakpoints and
memory inspection. The F072 exposes SWD on PA13/PA14.

### Wiring

| ST-Link | NanoVNA-H | Notes |
| --- | --- | --- |
| `3V3` | `3V3` | Use 3.3 V only, never the ST-Link 5 V pin |
| `GND` | `GND` | Common ground is required |
| `SWDIO` | `PA13` | |
| `SWCLK` | `PA14` | |
| `NRST` | `NRST` | Optional but recommended for connect-under-reset |

### Flash or recover

The script defaults to the official recovery image:

```bash
./scripts/recover-openocd.sh
```

To flash the unofficial image:

```bash
./scripts/recover-openocd.sh dist/unofficial/NanoVNA-H-1.3.1-omariglol.bin
```

If the application has disabled SWD or the MCU is not stopping, add
`--connect-under-reset` (this asserts NRST while connecting):

```bash
./scripts/recover-openocd.sh --connect-under-reset
```

The script runs OpenOCD through `sudo` by default because the ST-Link USB node
is normally root-owned. Use `--no-sudo` if your system has a udev rule for the
probe.

It installs `openocd` automatically if it is missing. `--install-udev` writes
the NanoVNA and ST-Link rules from [`scripts/99-nanovna-usbfix.rules`](../scripts/99-nanovna-usbfix.rules)
and [`scripts/99-stlink.rules`](../scripts/99-stlink.rules), then reloads
udev. `--install-deps` does both and also verifies/installs the pinned
`arm-none-eabi-gcc` 16.2.0 via
[`scripts/ci-install-toolchain.sh`](../scripts/ci-install-toolchain.sh). On
Arch, that installer runs `pacman -Syu`
and installs pinned package files, so it may perform a system upgrade; review
[`scripts/ci-install-toolchain.sh`](../scripts/ci-install-toolchain.sh) before
using `--install-deps` on a working host.

Manual equivalent:

```bash
sudo openocd -f interface/stlink.cfg -f target/stm32f0x.cfg \
  -c "program {dist/official/NanoVNA-H-1.3.1-omariglol-USB-PCLK.bin} \
      0x08000000 verify reset exit"
```

If the part is read-out protected, OpenOCD may refuse to connect. Use
STM32CubeProgrammer to remove protection first:

```bash
STM32_Programmer_CLI -c port=SWD mode=UR -e all \
  -w dist/official/NanoVNA-H-1.3.1-omariglol-USB-PCLK.bin 0x08000000 -v -rst
```

After recovery, set BOOT0 back to GND/low and power-cycle.

## UART bootloader rescue

The STM32F072 ROM bootloader also supports USART1, which is the same USART the
firmware uses for its serial console:

| Signal | NanoVNA-H pin | USB-UART adapter |
| --- | --- | --- |
| USART1_TX | `PA9` | adapter `RX` |
| USART1_RX | `PA10` | adapter `TX` |
| GND | `GND` | `GND` |
| 3.3 V | `3V3` | `3V3` |

Use 3.3 V TTL levels. BOOT0 must be high **at reset** (power-cycle after
changing the strap). The bootloader also supports USART2 on PA14/PA15 on some
parts; verify which pads your board exposes before soldering.

```bash
./scripts/recover-uart.sh -p /dev/ttyUSB0
# unofficial image:
./scripts/recover-uart.sh -p /dev/ttyUSB0 \
  dist/unofficial/NanoVNA-H-1.3.1-omariglol.bin
```

The script installs `stm32flash` automatically: the repo package on Debian, and
on Arch the AUR package (via `yay`, `paru`, or a direct `makepkg -si` build).
If the serial device is not writable by your user, the script falls back to
`sudo` unless `--no-sudo` is given. Use `--install-deps` to also install the
pinned `arm-none-eabi-gcc` 16.2.0 (used when the selected image has to be
rebuilt). It writes with verify and starts execution
at `0x08000000`. After that, set BOOT0 low and power-cycle.

If `stm32flash` cannot sync:

- Confirm the adapter is 3.3 V and its TX/RX are crossed relative to PA9/PA10.
- Confirm BOOT0 was high when the board was reset, not only when USB was
  plugged in.
- Disconnect any other device driving the USART1 console pins.
- Try a lower `-b` value (for example `-b 57600`) and a direct USB port.

## Profiling and stack inspection

Both release ELFs are built with `-ggdb` and `-fstack-usage`, so they contain
debug symbols and per-function static stack estimates.

- Official ELF:
  `dist/official/NanoVNA-H-1.3.1-omariglol-USB-PCLK.elf`
- Unofficial ELF:
  `dist/unofficial/NanoVNA-H-1.3.1-omariglol.elf`

### Runtime stack high-water mark

The unofficial image has a `stack` shell command (patch
`0006-ram0-stack-command`). Run it after exercising the worst-case paths
(calibration, SD writes, long shell commands, and `dump`):

```text
ch> stack
thread     size   free   used
sweep       872    136    736
main        576    116    460
```

These are measured values after RAM-2 (`0009-ram2-stack-sizes`). The `sweep`
worst case is the `dump` command, whose 408-byte local frame takes the thread
to 736 bytes including `thread_t`; that leaves 136 bytes of headroom. The
process stack was raised from 512 to 576 bytes because the boot path uses 460,
leaving only 52 bytes at the old size. Shell and SCPI commands execute in the
sweep thread, not on the main process stack.

`free` is the number of untouched bytes at the base of the working area,
measured from the ChibiOS fill pattern (`0x55`). `used = size - free` includes
the thread structure for `sweep`. The command runs in the main thread and scans
the `sweep` and `main` stacks, so it does not require
`CH_CFG_USE_REGISTRY`.

The official image has no `stack` command. Use GDB for both flavors when you
want an independent measurement.

### Static stack usage (both flavors)

`-fstack-usage` writes one `.su` file per object. To find the largest static
frames after a build:

```bash
find build/work/unofficial/build/obj -name '*.su' -exec cat {} + |
  sort -t$'\t' -k2 -n | tail -20
```

Use the same command with `build/work/official` for the official build. Large
static frames are candidates for the calibration and SD-write paths; confirm
them at runtime with `stack` or GDB.

### GDB with OpenOCD

Terminal 1, start the server:

```bash
openocd -f interface/stlink.cfg -f target/stm32f0x.cfg
```

Terminal 2, load the matching ELF:

```bash
arm-none-eabi-gdb dist/unofficial/NanoVNA-H-1.3.1-omariglol.elf
(gdb) target extended-remote :3333
(gdb) monitor reset halt
(gdb) break cal_done
(gdb) continue
```

Useful ChibiOS inspections:

```gdb
(gdb) p/x ch.mainthread.ctx.sp
(gdb) p/x ch.mainthread.wabase
(gdb) p *(thread_t *)((char *)waThread1 + sizeof(waThread1) - sizeof(thread_t))
(gdb) p/x ((thread_t *)((char *)waThread1 + sizeof(waThread1) - sizeof(thread_t)))->ctx.sp
(gdb) x/32bx waThread1
```

`waThread1` is file-static but visible in the ELF symbol table. The fill byte
is `0x55`; the first non-`0x55` byte from `wabase` upward marks the deepest
stack use. `CH_CFG_USE_REGISTRY` is disabled, so OpenOCD/GDB will not list
ChibiOS threads automatically; inspect the known `thread_t` structures
directly.

For coarse time profiling, halt periodically and sample `$pc`, or toggle a GPIO
around the function under test and measure it with a logic analyzer. The
Cortex-M0 in the F072 has no SWO/ETM instruction trace, so there is no
cycle-accurate hardware profiling path.

### HardFault triage

If the board hangs with no USB, attach and halt with OpenOCD:

```bash
openocd -f interface/stlink.cfg -f target/stm32f0x.cfg \
  -c "init" -c "halt" -c "reg" -c "shutdown"
```

If `current mode` is `Handler HardFault`, read the process stack pointer and
the exception frame it points at:

```bash
openocd -f interface/stlink.cfg -f target/stm32f0x.cfg \
  -c "init" -c "halt" -c "mdw 0x20001e38 8" -c "shutdown"
```

The frame is `R0 R1 R2 R3 R12 LR PC xPSR`; word 6 (`PC`) is the faulting
instruction. Map it back to source:

```bash
arm-none-eabi-addr2line -e dist/unofficial/NanoVNA-H-1.3.1-omariglol.elf \
  -f -C 0x0800b374
```

`CFSR`/`HFSR` can read zero after the fault has been latched, so the PSP frame
is the reliable record. This is how the `spi_buffer` bug was found: the faulting
store was in `draw_cell()`, writing a 32-bit value to a two-byte-aligned
`spi_buffer`. Fixing the declaration with `__attribute__((aligned(4)))` (patch
`0008`) restored USB enumeration.

### What differs between flavors

- **Official**: stock command set, no `stack` command. GDB, breakpoints and the
  `.su` files work exactly the same.
- **Unofficial**: adds USBTMC/SCPI, the `stack` command, and the `-Os` code
  build. SWD/OpenOCD recovery is identical.
