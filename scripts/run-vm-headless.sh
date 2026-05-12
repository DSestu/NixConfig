#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DISK_IMAGE="$REPO_ROOT/nixos-vm-headless.qcow2"

nix build '.#nixosConfigurations.nixos-vm-headless.config.system.build.vm'

# Pre-format the disk image with ext4 + label "nixos". The auto-generated
# wrapper only calls `mkfs` when `useDefaultFilesystems = true` (the
# qemu-vm module would otherwise inject its own `fileSystems."/"`). With
# our tmpfs root + ext4 `/nix` setup, we need to format the qcow2
# ourselves on first run.
if [ ! -e "$DISK_IMAGE" ]; then
  echo "Creating and formatting $DISK_IMAGE (ext4, label=nixos)..."
  nix shell nixpkgs#qemu nixpkgs#e2fsprogs --command bash -euo pipefail -c "
    raw=\$(mktemp)
    trap 'rm -f \$raw' EXIT
    qemu-img create -f raw \"\$raw\" 8G
    mkfs.ext4 -q -L nixos \"\$raw\"
    qemu-img convert -f raw -O qcow2 \"\$raw\" '$DISK_IMAGE'
  "
fi

# NB: do not pass `-snapshot` — it redirects all qcow2 writes to a temp
# file discarded on exit, which silently breaks impermanence persistence
# (`/nix/persist/...` writes never reach the disk image). Delete
# `nixos-vm-headless.qcow2` if you want a fresh state.
"$REPO_ROOT/result/bin/run-nixos-vm-headless-vm"
