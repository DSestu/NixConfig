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

title="agents: $name ${change:-${old_rev:0:7} → ${new_rev:0:7}}"

{
  echo "title=$title"
  echo "branch=agents/$name/${new_rev:0:7}"
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
