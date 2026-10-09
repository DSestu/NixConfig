#!/usr/bin/env bash
# Update one top-level flake input. Rewrites flake.lock in place and writes
# the PR title/branch/body to $GITHUB_OUTPUT (stdout when run locally).
# Prints nothing when the input is already current.
#
# Usage: ./scripts/flake-input-update.sh <input>     (needs gh auth)
set -euo pipefail
name=$1
out=${GITHUB_OUTPUT:-/dev/stdout}

# Untouched checkout for the package diff's "before" side.
old=$(mktemp -d)
git worktree add -q --detach "$old" HEAD
trap 'git worktree remove --force "$old"' EXIT

nix flake update "$name"
cmp -s flake.lock "$old/flake.lock" && exit 0

body=$(./scripts/flake-update-summary.sh "$old" .)

# Inputs carry no version, so the title names the change by, in order:
# 1. the one package whose version it bumps (pkg lists left in /tmp by
#    flake-update-summary.sh)
change=$(jq -rn --slurpfile o /tmp/old-pkgs.json --slurpfile n /tmp/new-pkgs.json '
  $o[0] as $o | [$n[0] | to_entries[] | select($o[.key] and $o[.key].v != .value.v)
    | "(\(.key) \($o[.key].v) → \(.value.v))"]
  | if length == 1 then .[0] else empty end')

lock() { jq -r --arg n "$name" ".nodes[.nodes.root.inputs[\$n]].locked.$2 // empty" "$1"; }
owner=$(lock flake.lock owner) repo=$(lock flake.lock repo)
old_rev=$(lock "$old/flake.lock" rev) new_rev=$(lock flake.lock rev)

# 2. the input repo's nearest git tags (commits-only clone). ponytail:
#    nixpkgs is skipped, too big to clone and its tags don't track unstable.
if [ -z "$change" ] && [ -n "$owner" ] && [ "${owner,,}/${repo,,}" != nixos/nixpkgs ]; then
  tags=$(mktemp -d)
  git clone -q --bare --filter=tree:0 "https://github.com/$owner/$repo" "$tags"
  describe() { git -C "$tags" describe --tags "$1" 2>/dev/null | sed 's/-\([0-9]*\)-g[0-9a-f]*$/+\1/'; }
  old_tag=$(describe "$old_rev") || true
  new_tag=$(describe "$new_rev") || true
  [ -n "$old_tag" ] && [ -n "$new_tag" ] && change="$old_tag → $new_tag"
fi

# 3. how many commits it moves.
if [ -z "$change" ] && [ -n "$owner" ]; then
  n=$(gh api "repos/$owner/$repo/compare/$old_rev...$new_rev" -q .total_commits)
  change="+$n commit$([ "$n" = 1 ] || echo s)"
fi

{
  echo "title=❄️ flake: $name ${change:-updated}"
  echo "branch=flake/$name/$(lock flake.lock lastModified)"
  echo "body<<EOF"
  echo "$body"
  echo "EOF"
} >> "$out"
