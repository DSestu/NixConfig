#!/usr/bin/env bash
# Update one top-level flake input. Rewrites flake.lock in place and writes
# the PR title/branch/body to $GITHUB_OUTPUT (stdout when run locally).
# Prints nothing when the input is already current.
#
# Usage: ./scripts/flake-input-update.sh <input>
set -euo pipefail
name=$1
out=${GITHUB_OUTPUT:-/dev/stdout}

# Untouched checkout for the package diff's "before" side.
old=$(mktemp -d)
git worktree add -q --detach "$old" HEAD
trap 'git worktree remove --force "$old"' EXIT

nix flake update "$name"
cmp -s flake.lock "$old/flake.lock" && exit 0

# Inputs carry no version, so name them by their commit date (plus the
# UTC time when both fall on the same day).
stamp() { jq -r --arg n "$name" '.nodes[.nodes.root.inputs[$n]].locked.lastModified' "$1"; }
old_t=$(stamp "$old/flake.lock") new_t=$(stamp flake.lock)
fmt="%Y-%m-%d"
[ "$(date -ud "@$old_t" +$fmt)" = "$(date -ud "@$new_t" +$fmt)" ] && fmt="%Y-%m-%d %H:%M"
change="$(date -ud "@$old_t" +"$fmt") → $(date -ud "@$new_t" +"$fmt")"

{
  echo "title=❄️ flake: $name $change"
  echo "branch=flake/$name/$new_t"
  echo "body<<EOF"
  ./scripts/flake-update-summary.sh "$old" .
  echo "EOF"
} >> "$out"
