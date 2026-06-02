#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DISK_IMAGE="$REPO_ROOT/nixos-vm.qcow2"

# ── agenix / SSH host key (Option B) ─────────────────────────────────────────
# This VM generates its SSH host key on first boot and stores it on the qcow2
# disk. To add it to secrets/ after first boot:
#   ssh-keyscan -p 2222 localhost | grep ed25519
#   # paste into secrets/secrets.nix, then rekey:
#   EDITOR=nano RULES=secrets/secrets.nix \
#     nix run github:ryantm/agenix -- --rekey -i ~/.ssh/id_ed25519
# ─────────────────────────────────────────────────────────────────────────────

nix build '.#nixosConfigurations.nixos-vm.config.system.build.vm'

# Pre-format the disk image with ext4 + label "nixos". nixos-vm uses
# impermanence (tmpfs root + ext4 /nix), so the disk must carry the
# "nixos" label before the VM boots — the initrd won't format it.
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
# file discarded on exit, which silently breaks impermanence persistence.
# Delete `nixos-vm.qcow2` if you want a fresh state.
"$REPO_ROOT/result/bin/run-nixos-vm-vm"
