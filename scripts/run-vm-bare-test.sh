#!/usr/bin/env bash
# Build the disko btrfs image for the `nixos-vm-bare-test` profile,
# boot it in qemu, and exercise the wipe-root behavior.
#
# This is the verification harness for SPEC.md Phase 4. It tests the
# *exact* code path that runs on real bare metal — wipe-root.nix's
# initrd service, the btrfs subvolume layout, and the
# environment.persistence map — without needing real hardware.
#
# Usage:
#   ./scripts/run-vm-bare-test.sh              # build image (if needed) + boot
#   ./scripts/run-vm-bare-test.sh --fresh      # delete image first, force rebuild
#   ./scripts/run-vm-bare-test.sh --boot-only  # skip build, just boot existing
#
# Verification recipe (manual):
#   1. First boot — log in as `david` (autologin on tty1, no password).
#      `journalctl -u wipe-canary-report` should print:
#        OK:   /root-canary absent  → @ was wiped (or first boot)
#        info: /nix/persist/persist-canary absent (first boot ...)
#   2. Seed canaries:
#        sudo touch /root-canary
#        sudo touch /nix/persist/persist-canary
#        touch ~/home-canary
#        sudo poweroff
#   3. Second boot — `journalctl -u wipe-canary-report` should print:
#        OK:   /root-canary absent  → @ was wiped
#        OK:   /nix/persist/persist-canary preserved across boot
#      And `ls ~/home-canary` should fail (strict /home wipe).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

IMAGE="$REPO_ROOT/nixos-vm-bare-test.qcow2"
PROFILE="nixos-vm-bare-test"

FRESH=0
BOOT_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --fresh)     FRESH=1 ;;
    --boot-only) BOOT_ONLY=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

if [ $FRESH -eq 1 ] && [ -e "$IMAGE" ]; then
  echo "--fresh: removing $IMAGE"
  rm -f "$IMAGE"
fi

if [ $BOOT_ONLY -eq 0 ] && [ ! -e "$IMAGE" ]; then
  echo "Building disko btrfs image for $PROFILE..."
  # Disko's `disko-images` mode builds raw images; we convert to qcow2
  # afterwards for snapshot/cow semantics during testing.
  TMP_DIR=$(mktemp -d)
  trap "rm -rf $TMP_DIR" EXIT

  nix run github:nix-community/disko -- \
    --mode disko-image \
    --flake ".#$PROFILE" \
    --root-mountpoint "$TMP_DIR/root"

  # disko-image writes "main.raw" by default for our single-disk layout.
  RAW="$REPO_ROOT/main.raw"
  if [ ! -e "$RAW" ]; then
    echo "expected $RAW from disko-image, not found" >&2
    ls -la "$REPO_ROOT" | head
    exit 1
  fi

  echo "Converting raw → qcow2..."
  nix shell nixpkgs#qemu --command qemu-img convert -f raw -O qcow2 "$RAW" "$IMAGE"
  rm -f "$RAW"
fi

if [ ! -e "$IMAGE" ]; then
  echo "no image at $IMAGE; run without --boot-only first" >&2
  exit 1
fi

echo "Booting $IMAGE..."
echo "Tip: 'sudo poweroff' inside the VM to shut down cleanly between boots."
echo

# UEFI firmware from nixpkgs; ovmf supplies the EFI variables.
OVMF=$(nix build --no-link --print-out-paths nixpkgs#OVMFFull.fd)

exec nix shell nixpkgs#qemu --command qemu-system-x86_64 \
  -enable-kvm \
  -cpu host \
  -smp 4 \
  -m 4096 \
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF/FV/OVMF_CODE.fd" \
  -drive "if=virtio,format=qcow2,file=$IMAGE,cache=writeback" \
  -netdev user,id=net0,hostfwd=tcp::2223-:22 \
  -device virtio-net-pci,netdev=net0 \
  -display gtk,gl=off \
  -vga virtio
