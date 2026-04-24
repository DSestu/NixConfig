#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

nix build '.#nixosConfigurations.nixos-vbox.config.system.build.virtualBoxOVA'
echo "OVA build complete. Import the .ova from: $REPO_ROOT/result/"
