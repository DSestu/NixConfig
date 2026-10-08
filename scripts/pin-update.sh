#!/usr/bin/env bash
# Bump one pins.nix entry to the current nixos-unstable head, if that
# changes the package's version. Rewrites pins.nix in place and writes
# the PR title/body to $GITHUB_OUTPUT (stdout when run locally). Prints
# nothing when the pin is already current.
#
# Usage: ./scripts/pin-update.sh <pkgAttr>
set -euo pipefail
name=$1
out=${GITHUB_OUTPUT:-/dev/stdout}

pin() { nix eval --impure --raw --expr "(import ./pins.nix { lib = {}; }).$name.$1"; }
# pkg <rev> <hash> <attr path under the package>
pkg() {
  nix eval --impure --raw --expr "((import (fetchTarball {
    url = \"https://github.com/NixOS/nixpkgs/archive/$1.tar.gz\"; sha256 = \"$2\";
  }) { config.allowUnfree = true; }).$name.$3 or \"\")"
}

old_rev=$(pin rev) old_hash=$(pin hash)
new_rev=$(git ls-remote https://github.com/NixOS/nixpkgs refs/heads/nixos-unstable | cut -f1)
[ "$old_rev" = "$new_rev" ] && exit 0
new_hash=sha256:$(nix-prefetch-url --unpack "https://github.com/NixOS/nixpkgs/archive/$new_rev.tar.gz" 2>/dev/null)

old_ver=$(pkg "$old_rev" "$old_hash" version)
new_ver=$(pkg "$new_rev" "$new_hash" version)
[ "$old_ver" = "$new_ver" ] && exit 0
changelog=$(pkg "$new_rev" "$new_hash" meta.changelog)
# meta.position is "/nix/store/<hash>-source/pkgs/…/package.nix:<line>"
file=$(pkg "$new_rev" "$new_hash" meta.position | sed 's|^/nix/store/[^/]*/||; s|:[0-9]*$||')

# Only touch this pin's block; also refresh a "# <version>" comment in it.
sed -i "/^  $name = {/,/};/{s/$old_rev/$new_rev/; s|$old_hash|$new_hash|; s|# $old_ver\$|# $new_ver|}" pins.nix

{
  echo "title=pins: $name $old_ver → $new_ver"
  echo "branch=pins/$name/$new_ver"
  echo "body<<EOF"
  echo "Moves the \`$name\` pin to the current \`nixos-unstable\` head."
  echo "Check the reason this package is pinned (comment in \`pins.nix\`) still applies before merging."
  echo
  echo "| | Version | nixpkgs rev |"
  echo "|---|---|---|"
  echo "| Old | $old_ver | [\`${old_rev:0:7}\`](https://github.com/NixOS/nixpkgs/tree/$old_rev) |"
  echo "| New | $new_ver | [\`${new_rev:0:7}\`](https://github.com/NixOS/nixpkgs/tree/$new_rev) |"
  echo
  [ -n "$changelog" ] && echo "- Changelog: $changelog"
  [ -n "$file" ] && echo "- Package history in nixpkgs: https://github.com/NixOS/nixpkgs/commits/$new_rev/$file"
  echo "EOF"
} >> "$out"
