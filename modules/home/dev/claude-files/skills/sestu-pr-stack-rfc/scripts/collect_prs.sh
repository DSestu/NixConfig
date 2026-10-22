#!/usr/bin/env bash
# Collect metadata, commits and diffs of a set of PRs into one folder.
#   collect_prs.sh <out-dir> <pr-number>...
# Run from inside the repo (gh resolves the repo from the remote).
set -euo pipefail

out="$1"
shift
mkdir -p "$out"

for pr in "$@"; do
  gh pr view "$pr" \
    --json number,title,body,state,isDraft,url,baseRefName,headRefName,additions,deletions,files,commits \
    > "$out/pr-$pr.json"
  gh pr diff "$pr" > "$out/pr-$pr.diff"
  jq -r '"#\(.number) \(.state)\(if .isDraft then " draft" else "" end) \(.headRefName) -> \(.baseRefName)  +\(.additions) -\(.deletions)\n  \(.title)\n  \(.url)\n" + ([.files[] | "  \(.path) (+\(.additions) -\(.deletions))"] | join("\n")) + "\n  commits:\n" + ([.commits[] | "    - \(.messageHeadline)\n      \(.messageBody | gsub("\n"; "\n      "))"] | join("\n"))' \
    "$out/pr-$pr.json"
  echo
done > "$out/summary.txt"

cat "$out/summary.txt"
