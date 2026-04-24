#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

nix build '.#nixosConfigurations.nixos-vm-headless.config.system.build.vm'
"$REPO_ROOT/result/bin/run-nixos-vm-headless-vm" -snapshot
