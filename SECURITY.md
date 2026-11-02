# Security policy

This is firmware for a bench instrument, not a network service. The relevant
security surface is the USB device stack and the DFU update path.

## Supported versions

Only the latest release artifacts are supported. Rebuild from the pinned
upstream tag and the current patches if you need an older configuration.

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could affect users flashing
the firmware. Contact the maintainers privately through the repository owner
(`acabtech`) or open a minimal issue asking for a private channel.

Please include:

- affected asset name and hash;
- host OS and kernel/libusb version;
- steps to reproduce;
- impact (enumeration, memory corruption, DFU, etc.).

## Scope

In scope:

- malformed USBTMC control or bulk requests causing a crash or memory corruption;
- buffer overflows in the SCPI command surface;
- unsafe DFU/update behavior introduced by this project.

Out of scope:

- upstream NanoVNA-H firmware bugs unrelated to the patches here;
- host-side libusb/omariglol issues (report those upstream);
- physical access attacks against the instrument.
