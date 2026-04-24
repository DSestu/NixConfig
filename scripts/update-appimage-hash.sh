#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  update-appimage-hash.sh <url>
  update-appimage-hash.sh <url> --replace <file> <old-sri-hash>

Examples:
  update-appimage-hash.sh "https://example.com/MyApp.AppImage"
  update-appimage-hash.sh "https://example.com/MyApp.AppImage" --replace modules/gaming.nix "sha256-OLD..."

Notes:
  - This script computes an SRI hash (sha256-...).
  - --replace performs a literal string replacement of <old-sri-hash> in <file>.
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

url="$1"
shift

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

echo "Downloading AppImage..."
curl -fsSL "$url" -o "$tmp_file"

new_hash="$(nix hash file --sri "$tmp_file")"
echo "Computed hash: $new_hash"

if [[ $# -eq 0 ]]; then
  exit 0
fi

if [[ $# -ne 3 || "$1" != "--replace" ]]; then
  usage
  exit 1
fi

target_file="$2"
old_hash="$3"

if [[ ! -f "$target_file" ]]; then
  echo "Error: file not found: $target_file" >&2
  exit 1
fi

if ! python - "$target_file" "$old_hash" "$new_hash" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
old_hash = sys.argv[2]
new_hash = sys.argv[3]
text = path.read_text()

if old_hash not in text:
    print(f"Error: old hash not found in {path}", file=sys.stderr)
    raise SystemExit(1)

path.write_text(text.replace(old_hash, new_hash))
print(f"Updated {path}")
PY
then
  exit 1
fi

echo "Done."
