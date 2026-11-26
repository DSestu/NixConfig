# Helpers sourced by the update-deps bump scripts.

# clone_commits <dir> <owner> <repo>: commits-only bare clone; enough for
# describe_rev and git log, no trees or blobs.
clone_commits() { git clone -q --bare --filter=tree:0 "https://github.com/$2/$3" "$1"; }

# describe_rev <clone> <rev>: nearest tag, as v5.1.0 or v5.1.0+3 for
# 3 commits past it. Prints nothing (non-zero exit) when untagged.
describe_rev() { git -C "$1" describe --tags "$2" 2>/dev/null | sed 's/-\([0-9]*\)-g[0-9a-f]*$/+\1/'; }
