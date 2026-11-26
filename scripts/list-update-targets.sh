#!/usr/bin/env bash
# JSON matrix for update-deps.yml: one {script, name} per pins.nix entry,
# auto-updating agent-sources.nix entry, and top-level flake input.
#
# Usage: ./scripts/list-update-targets.sh
set -euo pipefail
# shellcheck disable=SC2016  # ${…} below is Nix interpolation
nix eval --impure --json --expr '
  let
    agents = import ./modules/home/dev/agent-sources.nix { pkgs = {}; lib = {}; };
    sources = agents.marketplaces // agents.skillRepos;
    each = script: map (name: { inherit script name; });
  in
    each "pin-update.sh" (builtins.attrNames (import ./pins.nix { lib = {}; }))
    ++ each "agent-source-update.sh" (builtins.filter (n: sources.${n}.autoUpdate or true) (builtins.attrNames sources))
    ++ each "flake-input-update.sh" (builtins.attrNames (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.root.inputs)
'
