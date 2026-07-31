# ns — throwaway shells. One command, three "worlds" that differ only in how
# the filesystem behaves; packages and the run-vs-interactive-shell choice
# compose on top of any of them. See docs/spec-ephemeral-shells.md and the
# `ns -h` banner (function __ns_help below).
#
#   live (default)     your real system + extra nix packages on PATH
#   ! / -i/--isolated  walled-off empty world; sees/touches nothing real
#   @ / -r/--rehearse  your real files, but every change is discarded (COW)
#
# This file is self-contained: it defines `ns` plus its private `__ns_*`
# helpers, so it works dropped into any fish (see modules/dual/ns/README.md)
# as well as via the Nix module (modules/dual/ns/default.nix).

function __ns_help
    # Canonical help banner (spec §2). Plain text so it renders anywhere.
    echo 'ns — throwaway shells. Spawn an ephemeral shell in one of three worlds.'
    echo
    echo 'USAGE'
    echo '  ns [MODE] [pkg ...] [ -- | cmd ... ]'
    echo
    echo 'MODES  (how the filesystem behaves; default = your live system)'
    echo '  -i, --isolated  (!)   WALLED  empty world; can'\''t see or touch anything real'
    echo '  -r, --rehearse  (@)   GHOST   your real files, but every change is discarded'
    echo
    echo 'PACKAGES & SHELL  (compose with any mode)'
    echo '  ns rg fd --           interactive shell with rg + fd on PATH'
    echo '  ns rg -n foo .        run one command, then exit'
    echo '  ns -i                 (mode alone) → interactive shell in that world'
    echo
    echo 'OPTIONS'
    echo '  -N, --no-net          cut off the network (isolated + rehearse)'
    echo '  URL                   git-clone URL into the shell first (isolated/rehearse)'
    echo '  -h, --help            show this'
    echo
    echo 'EXAMPLES'
    echo '  ns jq --                      quick shell with jq'
    echo '  ns -i https://github/x -N     clone a sketchy repo, isolated + offline'
    echo '  ns -r just deploy             rehearse `just deploy`, then revert it all'
end

# Live mode: the original `ns` behavior, unchanged. First arg is a package
# that is also the command to run (with the rest as its args); a trailing `--`
# instead means "interactive shell with all preceding tokens as packages".
# Resolves via the `nixpkgs` flake registry entry.
function __ns_live
    if test (count $argv) -eq 0
        __ns_help
        return 0
    end

    if test $argv[-1] = '--'
        set -l pkgs $argv[1..-2]
        if test (count $pkgs) -eq 0
            echo 'ns: give at least one package before `--`' >&2
            return 1
        end
        # NS_MODE=live + NS_INFO=<packages> drive the Tide packages badge
        # (flask). Exported so they survive Tide's background `fish -c` render
        # child. Live has no mode/net badge — just the flask + package list.
        set -l badge (string join ' ' $pkgs)
        env NS_MODE=live NS_INFO=$badge nix shell nixpkgs#$pkgs
    else
        set -l pkg $argv[1]
        set -l rest $argv[2..-1]
        nix shell nixpkgs#$pkg --command $pkg $rest
    end
end

# Rehearse overlay: for every top-level directory, stack a copy-on-write
# `--tmp-overlay` (writes captured in a throwaway tmpfs over the real dir as
# read-only lower). Dirs that can't be an overlay lowerdir — an unsupported
# fstype (vfat …) or one CONTAINING a nested mount (e.g. /boot holding the
# vfat /boot/efi) — are passed through read-only instead. Root symlinks
# (merged-usr) are recreated; virtual mounts are provided fresh. Sets the
# bwrap arg list in $__ns_ba. $argv[1]=no_net(0|1) $argv[2]=netlabel.
function __ns_overlay_args
    set -l no_net $argv[1]
    set -l netlabel $argv[2]

    if not type -q findmnt
        echo 'ns: findmnt not found (util-linux) — cannot map mounts for rehearse' >&2
        return 1
    end

    set -l capable ext2 ext3 ext4 btrfs xfs zfs f2fs jfs reiserfs
    set -l virtual /proc /sys /dev /run /tmp
    set -l allmounts (findmnt -rno TARGET)

    set -l args
    set -l overlaid
    set -l robound
    for e in /*
        contains -- $e $virtual; and continue
        if test -L $e
            set -a args --symlink (readlink $e) $e
            continue
        end
        test -d $e; or continue
        test -r $e; or continue # skip 0700 dirs like /root, /lost+found
        set -l fst (findmnt -no FSTYPE -T $e 2>/dev/null | tail -1)
        if contains -- $fst $capable; and not string match -q -- "$e/*" $allmounts
            set -a args --overlay-src $e --tmp-overlay $e
            set -a overlaid $e
        else
            set -a args --ro-bind-try $e $e
            set -a robound $e
        end
    end

    echo "ns: rehearse — every change is discarded on exit; network $netlabel." >&2
    echo "  copy-on-write (revertible): $overlaid" >&2
    test -n "$robound"; and echo "  read-only passthrough:      $robound" >&2

    # Rehearse is deliberately NOT isolated (real PIDs, real /run). Net is on
    # by default (bwrap doesn't unshare it); --no-net adds --unshare-net.
    set -l netarg
    test "$no_net" = 1; and set netarg --unshare-net

    set -g __ns_ba $args \
        --dev /dev \
        --proc /proc \
        --ro-bind-try /sys /sys \
        --tmpfs /tmp \
        --bind-try /run /run \
        --chdir $PWD \
        --setenv NS_MODE rehearse \
        $netarg \
        --die-with-parent
    return 0
end

# Shared driver for the two sandboxed modes. Parses the common grammar —
# leading `-N`/`--no-net`, an optional `URL` to clone, then
# `[pkg ...] [-- | cmd ...]` exactly like live — builds mode-specific bwrap
# args, and runs. Requested packages are put on PATH inside by wrapping the
# whole bwrap call in `nix shell nixpkgs#$pkgs --command …` (bwrap inherits
# the augmented PATH; /nix is mounted, so the binaries resolve).
#   $argv[1] = mode (isolated|rehearse); rest = user tokens after the mode.
function __ns_box
    set -l mode $argv[1]
    set -e argv[1]

    if not type -q bwrap
        echo 'ns: bwrap not found — install bubblewrap (see modules/dual/ns/README.md)' >&2
        return 1
    end

    # --- leading options: -N/--no-net, then an optional clone URL ---
    set -l no_net 0
    if set -q argv[1]; and contains -- $argv[1] -N --no-net
        set no_net 1
        set -e argv[1]
    end
    set -l clone_url ''
    if set -q argv[1]; and string match -rq -- '://|^git@|\.git$' $argv[1]
        set clone_url $argv[1]
        set -e argv[1]
    end

    # --- remaining tokens → packages + inner command (same grammar as live) ---
    #   trailing `--` : interactive shell, preceding tokens are packages
    #   otherwise     : first token is the package AND the command to run
    set -l pkgs
    set -l inner
    if set -q argv[1]; and test $argv[-1] = '--'
        set pkgs $argv[1..-2]
        set inner fish
    else if set -q argv[1]
        set pkgs $argv[1]
        set inner $argv
    else
        set inner fish
    end

    set -l netlabel net
    test "$no_net" = 1; and set netlabel no-net

    # Mode-badge info: just the requested package names (if any). The network
    # state is a SEPARATE badge (NS_NET) with its own icon, so "isolated" is
    # never confused with "network isolated".
    set -l info ''
    test (count $pkgs) -gt 0; and set info (string join ' ' $pkgs)

    set -l ba
    set -l cleanup ''

    if test $mode = isolated
        # Empty writable /work is the only writable path; everything else the
        # shell sees is read-only (or absent). The clone happens on the host
        # into the scratch dir (safe — it's a temp dir, trashed on exit).
        set -l work (mktemp -d)
        set -l chdir /work

        # Writable copy of the fish config so the shell keeps its theme yet can
        # write fish_variables/history. `-L` dereferences HM symlinks; store
        # binaries stay reachable via the read-only /nix bind.
        if test -d $HOME/.config/fish
            mkdir -p $work/.config
            cp -rL $HOME/.config/fish $work/.config/fish
            chmod -R u+w $work/.config/fish
        end

        if test -n "$clone_url"
            echo "ns: cloning $clone_url into an ephemeral checkout…" >&2
            if not git clone --depth 1 $clone_url $work/repo
                rm -rf $work
                return 1
            end
            set chdir /work/repo
        end

        echo "ns: isolated shell — writable /work only, network $netlabel; exit to destroy everything." >&2

        set -l netarg --share-net
        test "$no_net" = 1; and set netarg --unshare-net

        set ba \
            --ro-bind /nix /nix \
            --ro-bind-try /usr /usr \
            --ro-bind-try /bin /bin \
            --ro-bind-try /lib /lib \
            --ro-bind-try /lib64 /lib64 \
            --ro-bind-try /etc /etc \
            --ro-bind-try /run /run \
            --proc /proc \
            --dev /dev \
            --tmpfs /tmp \
            --bind $work /work \
            --chdir $chdir \
            --setenv HOME /work \
            --setenv NS_MODE isolated \
            --unshare-all $netarg \
            --die-with-parent
        set cleanup $work
    else
        # rehearse: copy-on-write over the real filesystem.
        if not __ns_overlay_args $no_net $netlabel
            return 1
        end
        set ba $__ns_ba

        # The clone must happen INSIDE the overlay (a host clone would write to
        # the real cwd and persist). Prepend it to the inner command so it
        # lands in the throwaway upper layer and reverts on exit.
        if test -n "$clone_url"
            set -l prelude "git clone --depth 1 $clone_url repo; and cd repo"
            if test "$inner" = fish
                set inner fish -C $prelude
            else
                set inner fish -C $prelude -c (string join ' ' (string escape -- $inner))
            end
        end
    end

    # NS_INFO (packages) drives the mode badge; NS_NET (net/no-net) drives the
    # separate network badge — both read by the Tide integration.
    set -a ba --setenv NS_INFO $info --setenv NS_NET $netlabel

    # --- run: put requested packages (and any module-configured
    # extraPackages) on PATH inside by wrapping bwrap in `nix shell`. Only
    # wrap when there is at least one package, so a plain shell stays cheap.
    # $__ns_extra_refs is set by the module's conf.d (already `nixpkgs#name`).
    set -l refs
    for p in $pkgs
        set -a refs nixpkgs#$p
    end
    set -a refs $__ns_extra_refs
    if test (count $refs) -gt 0
        nix shell $refs --command bwrap $ba $inner
    else
        bwrap $ba $inner
    end
    set -l rc $status

    test -n "$cleanup"; and rm -rf $cleanup
    return $rc
end

function ns --description 'throwaway shells: live (default), ! isolated, @ rehearse (ns -h)'
    # Help: `ns -h`, `ns --help`, or a bare `ns`.
    if test (count $argv) -eq 0
        __ns_help
        return 0
    end
    if contains -- $argv[1] -h --help
        __ns_help
        return 0
    end

    # Leading MODE selector (flag, short, or fish-safe sigil). Only honored as
    # the first token, so it never collides with a package name later.
    set -l mode live
    switch $argv[1]
        case -i --isolated '!'
            set mode isolated
            set -e argv[1]
        case -r --rehearse '@'
            set mode rehearse
            set -e argv[1]
    end

    if test $mode = live
        __ns_live $argv
        return $status
    end

    __ns_box $mode $argv
end
