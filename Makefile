SHELL := /bin/bash
VERSION ?= 1.2.50

.PHONY: all official unofficial dist verify clean fetch help recover recover-uart

all: official unofficial

official:
	./scripts/build.sh official

unofficial:
	./scripts/build.sh unofficial

dist: all verify

verify:
	./scripts/verify.sh

fetch:
	./scripts/fetch-upstream.sh

recover:
	./scripts/recover-openocd.sh $(IMAGE)

recover-uart:
	./scripts/recover-uart.sh $(IMAGE)

clean:
	rm -rf build dist

help:
	@echo "Targets:"
	@echo "  make official        build the stock firmware + PCLK USB-clock fix"
	@echo "  make unofficial      build the PCLK fix + USBTMC/SCPI USB API"
	@echo "  make all             both firmware flavors"
	@echo "  make dist            build both and verify artifacts"
	@echo "  make recover         flash/recover over ST-Link (OpenOCD)"
	@echo "  make recover-uart    flash/recover over the ROM UART bootloader"
	@echo "  make fetch           unpack the pinned upstream source for inspection"
	@echo "  make clean           remove build/ and dist/"
	@echo ""
	@echo "  IMAGE=<file.bin> selects a non-default recovery image for recover targets"
