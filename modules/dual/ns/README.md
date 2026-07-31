# `ns` — throwaway shells

One command, three ephemeral "worlds" that differ only in **how the
filesystem behaves**. Adding packages and choosing run-a-command vs.
interactive-shell compose on top of any world.

```
ns rg -n foo .        live: run a tool ephemerally, then exit
ns rg fd --           live: interactive shell with rg + fd on PATH
ns !                  isolated: walled-off empty world (sees nothing real)
ns ! URL -N           isolated: clone URL, no network
ns @                  rehearse: your REAL files, every change reverts on exit
ns @ just deploy      rehearse: run it for real, then discard all changes
ns -h                 full help
```

| Mode | Flag / sigil | Sees real files | Writes persist |
|------|--------------|:---:|:---:|
| live | *(default)* | yes | **yes** |
| isolated | `-i` / `--isolated` / `!` | **no** (empty `/work`) | no |
| rehearse | `-r` / `--rehearse` / `@` | yes | **no** (copy-on-write) |

`-N`/`--no-net` cuts the network in the sandbox modes; a `URL` first argument
is git-cloned into the shell (isolated → `/work`, rehearse → `./<repo>`,
reverting on exit).

## Required packages

Install these and make sure they're on `PATH`:

| Package | Provides | Needed for |
|---------|----------|------------|
| `fish` | the shell | everything |
| `bubblewrap` | `bwrap` | `!` isolated + `@` rehearse |
| `util-linux` | `findmnt` | `@` rehearse (enumerate mounts) |
| `git` | `git` | cloning a `URL` |
| `coreutils` | `mktemp`, `cp`, `chmod`, `readlink`, `tail` | isolated setup (usually already present) |
| `nix` | `nix shell` | live mode, and putting packages on PATH inside any mode |

Notes:
- `!` (isolated) and `@` (rehearse) work on **any Linux**; only the "packages
  on PATH" feature needs Nix.
- `@` (rehearse) needs **unprivileged overlayfs** — a kernel ≈5.11+ that
  allows overlay mounts inside a user namespace (most modern distros). No
  root or setuid is required.

## Use in an arbitrary fish (no Nix module)

1. Copy the command into your fish functions directory:
   ```sh
   cp ns.fish ~/.config/fish/functions/ns.fish
   ```
   `ns.fish` is a complete, self-contained `function ns … end` file (it also
   defines its private `__ns_*` helpers), so nothing else is required for the
   command itself.
2. Install the required packages above with your OS package manager.
3. (Optional) ctrl+f discoverability: this repo's `browse_functions` reads a
   `$__user_browse_functions` global; if you use that picker, add
   `set -ga __user_browse_functions ns` to a `conf.d` file. Skip otherwise.

### Optional Tide prompt theming

If you use the [Tide](https://github.com/IlanCosman/tide) prompt, copy the
theming file into `conf.d` so it loads **after** your base theme and
**before** Tide bakes its prompt:

```sh
cp ns-tide.fish ~/.config/fish/conf.d/20-ns-tide.fish
```

It adds a single right-prompt item `ns` whose color/icon/label follow the
`NS_MODE` marker the command exports (flask = live, cube = isolated,
recycle = rehearse), plus **Level-3 accents**: in `!`/`@` the prompt
character and the PWD segment take the mode color (sand / violet) so you
can't forget which world you're in. Requires a Nerd Font (for the glyphs).
No effect in normal shells.

## Use as a Nix module (Home Manager / NixOS)

The flake exposes `homeManagerModules.ns` and `nixosModules.ns`.

```nix
# flake inputs:
#   nsbox.url = "github:DSestu/NixConfig";
# home-manager or nixos config:
imports = [ inputs.nsbox.homeManagerModules.ns ]; # or nixosModules.ns
programs.ns = {
  enable = true;
  tideBadges.enable = true;          # optional; off by default
  extraPackages = [ pkgs.jq ];       # optional; always on PATH inside every ns shell
};
```

The module installs `ns.fish` (HM: `~/.config/fish/functions/`; NixOS: a fish
`vendor_functions.d` entry), pulls the runtime dependencies above (except
`nix`, assumed present), and — when `tideBadges.enable` — ships the Tide
integration. `extraPackages` are injected onto `PATH` inside every mode via
`nix shell` (their nixpkgs attribute is derived with `lib.getName`; a package
whose attribute differs from its pname may instead need to be requested by
name at the prompt).
