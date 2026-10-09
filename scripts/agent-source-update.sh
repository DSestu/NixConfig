#!/usr/bin/env bash
# Bump one agent-sources.nix entry (marketplace or skill repo) to its repo's
# default-branch HEAD, refreshing hash and plugin.json versions. Rewrites
# agent-sources.nix in place and writes the PR title/branch/body to
# $GITHUB_OUTPUT (stdout when run locally). Prints nothing when current.
#
# Usage: ./scripts/agent-source-update.sh <name>     (needs gh auth)
set -euo pipefail
name=$1
file=modules/home/dev/agent-sources.nix
out=${GITHUB_OUTPUT:-/dev/stdout}

src=$(nix eval --impure --json --expr \
  "let s = import ./$file { pkgs = {}; lib = {}; }; in (s.marketplaces // s.skillRepos).\"$name\"")
owner=$(jq -r .owner <<<"$src") repo=$(jq -r .repo <<<"$src")
old_rev=$(jq -r .rev <<<"$src") old_hash=$(jq -r .hash <<<"$src")

new_rev=$(git ls-remote "https://github.com/$owner/$repo" HEAD | cut -f1)
[ "$old_rev" = "$new_rev" ] && exit 0
new_hash=$(nix flake prefetch --json "github:$owner/$repo/$new_rev" | jq -r .hash)

# ponytail: global replace; fine while no two entries share a rev or hash.
sed -i "s/$old_rev/$new_rev/; s|$old_hash|$new_hash|" "$file"

# Plugin versions, from each plugin's .claude-plugin/plugin.json.
versions=""
while IFS=$'\t' read -r plugin sub old_ver; do
  [ -n "$plugin" ] || continue
  new_ver=$(curl -fsSL "https://raw.githubusercontent.com/$owner/$repo/$new_rev/${sub:+$sub/}.claude-plugin/plugin.json" |
    jq -r '.version // empty') || true
  [ -n "$new_ver" ] && [ "$new_ver" != "$old_ver" ] || continue
  sed -i "/^        $plugin = {/,/};/ s/version = \"$old_ver\"/version = \"$new_ver\"/" "$file"
  versions+="| $plugin | $old_ver | $new_ver |"$'\n'
  change=${change:-$old_ver → $new_ver}
done < <(jq -r '.plugins // {} | to_entries[] | [.key, .value.pluginSubpath, .value.version] | @tsv' <<<"$src")

# Name each rev by its nearest git tag (v5.1.0, or v5.1.0+3 for 3 commits
# past it). Commits-only clone: describe needs no trees or blobs.
tags=$(mktemp -d)
git clone -q --bare --filter=tree:0 "https://github.com/$owner/$repo" "$tags"
describe() { git -C "$tags" describe --tags "$1" 2>/dev/null | sed 's/-\([0-9]*\)-g[0-9a-f]*$/+\1/'; }
# No tag and no plugin.json bump means no version: use commit dates.
commit_date() { git -C "$tags" log -1 --format=%cs "$1"; }
old_tag=$(describe "$old_rev") || true
new_tag=$(describe "$new_rev") || true
[ -n "$new_tag" ] && change="${old_tag:-$(commit_date "$old_rev")} → $new_tag"
change=${change:-$(commit_date "$old_rev") → $(commit_date "$new_rev")}

{
  echo "title=🤖 agents: $name $change"
  echo "branch=agents/$name/${change##* }"
  echo "body<<EOF"
  echo "Moves \`$name\` ([$owner/$repo](https://github.com/$owner/$repo)) to its latest commit."
  echo "Claude Code and Cursor both pick this up (shared via \`agent-sources.nix\`)."
  echo
  if [ -n "$versions" ]; then
    echo "| Plugin | Old | New |"
    echo "|---|---|---|"
    printf '%s' "$versions"
    echo
  fi
  echo "### Commits ([full diff](https://github.com/$owner/$repo/compare/$old_rev...$new_rev))"
  echo
  gh api "repos/$owner/$repo/compare/$old_rev...$new_rev" \
    --jq '.commits | reverse | .[:50][] | "- [`\(.sha[:7])`](\(.html_url)) \(.commit.message | split("\n")[0])"'
  echo "EOF"
} >> "$out"
