#!/usr/bin/env bash
# Markdown summary of a flake.lock update, for the update-flake-lock PR body.
# Eval-only (no builds): lists changed flake inputs with GitHub compare
# links, then package version changes with each package's meta.changelog.
#
# Usage: ./scripts/flake-update-summary.sh <old-checkout> <new-checkout>
set -euo pipefail
old=$1 new=$2

# Packages the user actually gets: standalone HM + the desktop system.
targets=(
  homeConfigurations.david.config.home.packages
  nixosConfigurations.nixos-desktop.config.environment.systemPackages
  nixosConfigurations.nixos-desktop.config.home-manager.users.david.home.packages
)
apply='map (p: let d = builtins.parseDrvName (p.name or ""); in {
  n = p.pname or d.name; v = p.version or d.version; c = p.meta.changelog or null; })'

pkgs() {
  for t in "${targets[@]}"; do
    nix eval --json "$1#$t" --apply "$apply" 2>/dev/null || echo '[]'
  done | jq -s 'add | map(select(.v != "")) | INDEX(.n)'
}

echo "## Inputs"
echo
jq -rn --slurpfile o "$old/flake.lock" --slurpfile n "$new/flake.lock" '
  $n[0].nodes | to_entries[]
  | select(.value.locked.type == "github")
  | .key as $k | .value.locked as $l | ($o[0].nodes[$k].locked.rev // null) as $old
  | select($old != $l.rev)
  | if $old then "- **\($k)**: [`\($old[:7])...\($l.rev[:7])`](https://github.com/\($l.owner)/\($l.repo)/compare/\($old)...\($l.rev))"
    else "- **\($k)**: added at `\($l.rev[:7])`" end'
echo

pkgs "$old" > /tmp/old-pkgs.json
pkgs "$new" > /tmp/new-pkgs.json

echo "## Packages"
echo
jq -rn --slurpfile o /tmp/old-pkgs.json --slurpfile n /tmp/new-pkgs.json '
  $o[0] as $o | $n[0] as $n
  | ([$n | keys[] | select($o[.] and $o[.].v != $n[.].v)
      | "| \(.) | \($o[.].v) | \($n[.].v) | \(if $n[.].c then "[changelog](\($n[.].c))" else "" end) |"]) as $changed
  | ([$n | keys[] | select($o[.] | not) | "| \(.) | | \($n[.].v) | added |"]) as $added
  | ([$o | keys[] | select($n[.] | not) | "| \(.) | \($o[.].v) | | removed |"]) as $removed
  | ($changed + $added + $removed) as $rows
  | if ($rows | length) == 0 then "No package version changes."
    else "| Package | Old | New | Changelog |\n|---|---|---|---|\n" + ($rows | join("\n")) end'
