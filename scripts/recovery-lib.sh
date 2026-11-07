#!/usr/bin/env bash
#
# Shared helpers for scripts/recover-*.sh. Source this file; do not execute it.
# shellcheck shell=bash

RECOVERY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECOVERY_EXPECTED_GCC="16.2.0"
# Largest image region any flavor can produce since FLASH-1: the official
# flash0 is 114 KiB. Recovery accepts either flavor, so the limit is the larger
# one; a corrupt image still fails the vector-table checks below.
RECOVERY_FLASH_MAX=116736
RECOVERY_IMAGE=""
RECOVERY_IMAGE_SIZE=0
RECOVERY_INSTALL_DEPS="${RECOVERY_INSTALL_DEPS:-0}"

recovery_log() { echo "==> $*"; }
recovery_warn() { echo "warning: $*" >&2; }
recovery_die() { echo "error: $*" >&2; exit 1; }

recovery_have() { command -v "$1" >/dev/null 2>&1; }

recovery_as_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  elif recovery_have sudo; then
    sudo "$@"
  else
    recovery_die "root privileges required; install sudo or run as root"
  fi
}

recovery_pm() {
  if recovery_have pacman; then
    echo pacman
  elif recovery_have apt-get; then
    echo apt
  else
    echo unknown
  fi
}

recovery_install_repo_pkg() {
  # $1 = command, $2 = Arch package, $3 = Debian package
  local cmd="$1" arch="$2" deb="$3" pm
  recovery_have "$cmd" && return 0
  pm="$(recovery_pm)"
  case "$pm" in
    pacman)
      recovery_log "installing $arch"
      recovery_as_root pacman -S --noconfirm --needed "$arch" ||
        recovery_die "failed to install $arch"
      ;;
    apt)
      recovery_log "installing $deb"
      recovery_as_root apt-get update || true
      recovery_as_root apt-get install -y "$deb" ||
        recovery_die "failed to install $deb"
      ;;
    *)
      recovery_die "missing $cmd; install the '$arch'/'$deb' package manually"
      ;;
  esac
  recovery_have "$cmd" || recovery_die "$cmd is still missing after installation"
}

recovery_install_stm32flash() {
  recovery_have stm32flash && return 0
  local pm helper tmp
  pm="$(recovery_pm)"

  if [[ "$pm" == "apt" ]]; then
    recovery_install_repo_pkg stm32flash stm32flash stm32flash
    return
  fi

  if [[ "$pm" == "pacman" ]]; then
    # Try the repos first; on Arch stm32flash is normally AUR-only.
    if recovery_as_root pacman -S --noconfirm --needed stm32flash >/dev/null 2>&1; then
      recovery_have stm32flash && return 0
    fi
    [[ $EUID -eq 0 ]] &&
      recovery_die "stm32flash is AUR-only; install it as a normal user with 'yay -S stm32flash' or 'paru -S stm32flash'"

    for helper in yay paru; do
      if recovery_have "$helper"; then
        recovery_log "installing stm32flash from the AUR with $helper"
        "$helper" -S --needed --noconfirm stm32flash ||
          recovery_die "$helper failed to install stm32flash"
        recovery_have stm32flash && return 0
      fi
    done

    # Last resort: build the AUR package directly as the invoking user.
    if recovery_have git && recovery_have makepkg; then
      recovery_log "building stm32flash from the AUR"
      tmp="$(mktemp -d)"
      git clone --depth 1 https://aur.archlinux.org/stm32flash.git \
        "$tmp/stm32flash" || {
        rm -rf "$tmp"
        recovery_die "could not clone the stm32flash AUR package"
      }
      (cd "$tmp/stm32flash" && makepkg -si --noconfirm) || {
        rm -rf "$tmp"
        recovery_die "makepkg failed for stm32flash"
      }
      rm -rf "$tmp"
      recovery_have stm32flash && return 0
    fi

    recovery_die "stm32flash is AUR-only on Arch; install it with 'yay -S stm32flash' or 'paru -S stm32flash'"
  fi

  recovery_die "missing stm32flash; install it with your package manager"
}

recovery_install_udev() {
  recovery_log "installing udev rules (NanoVNA + ST-Link)"
  recovery_as_root "$RECOVERY_ROOT/scripts/install-udev.sh"
}

recovery_gcc_version() {
  if recovery_have arm-none-eabi-gcc; then
    arm-none-eabi-gcc -dumpversion
  fi
}

recovery_require_pinned_toolchain() {
  local version
  version="$(recovery_gcc_version)"
  [[ "$version" == "$RECOVERY_EXPECTED_GCC" ]] && return 0

  if [[ "$RECOVERY_INSTALL_DEPS" == "1" ]]; then
    recovery_log "installing pinned arm-none-eabi-gcc $RECOVERY_EXPECTED_GCC"
    recovery_as_root env \
      PKG_CACHE="${PKG_CACHE:-/var/cache/nanovna-toolchain}" \
      "$RECOVERY_ROOT/scripts/ci-install-toolchain.sh"
    version="$(recovery_gcc_version)"
    [[ "$version" == "$RECOVERY_EXPECTED_GCC" ]] ||
      recovery_die "toolchain is ${version:-missing}, expected $RECOVERY_EXPECTED_GCC"
    return 0
  fi

  recovery_die "arm-none-eabi-gcc ${version:-missing} does not match pinned $RECOVERY_EXPECTED_GCC; rerun with --install-deps or run: sudo scripts/ci-install-toolchain.sh"
}

recovery_build_image() {
  local flavor="$1"
  recovery_require_pinned_toolchain
  recovery_log "building the $flavor image with the pinned toolchain"
  make -C "$RECOVERY_ROOT" "$flavor"
}

recovery_check_image() {
  local file="$1" sp reset
  [[ -f "$file" ]] || recovery_die "missing firmware: $file"

  RECOVERY_IMAGE_SIZE="$(stat -c%s "$file")"
  if (( RECOVERY_IMAGE_SIZE == 0 || RECOVERY_IMAGE_SIZE > RECOVERY_FLASH_MAX )); then
    recovery_die "$file is $RECOVERY_IMAGE_SIZE bytes; expected 1..$RECOVERY_FLASH_MAX"
  fi

  # Validate the Cortex-M vector table so a .hex/.elf or unrelated file is
  # rejected before it reaches the target.
  read -r sp reset < <(od -An -tx4 -N8 "$file")
  if (( 0x$sp < 0x20000000 || 0x$sp > 0x20004000 )); then
    recovery_die "$file does not start with a valid Cortex-M stack pointer (0x$sp)"
  fi
  if (( 0x$reset < 0x08000000 || 0x$reset > 0x08020000 )); then
    recovery_die "$file does not start with a valid reset vector (0x$reset)"
  fi
}

recovery_resolve_image() {
  # $1 = requested file (may be empty), $2 = default flavor
  local file="$1" flavor="$2"
  if [[ -z "$file" ]]; then
    case "$flavor" in
      official)
        file="$RECOVERY_ROOT/dist/official/NanoVNA-H-1.3.1-omariglol-USB-PCLK.bin"
        ;;
      unofficial)
        file="$RECOVERY_ROOT/dist/unofficial/NanoVNA-H-1.3.1-omariglol.bin"
        ;;
      *)
        recovery_die "unknown flavor: $flavor"
        ;;
    esac
  fi

  if [[ ! -f "$file" ]]; then
    case "$file" in
      */official/*) recovery_build_image official ;;
      */unofficial/*) recovery_build_image unofficial ;;
      *) recovery_die "missing firmware: $file" ;;
    esac
  fi

  recovery_check_image "$file"
  RECOVERY_IMAGE="$file"
}
