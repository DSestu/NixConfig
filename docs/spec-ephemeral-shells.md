# Spec — unified ephemeral-shell command (`ns`)

Status: **APPROVED** — implementation in progress (see `tasks/todo.md`)
Scope: `modules/dual/fish.nix`, `modules/dual/fish_config/tide-theme.fish`,
`modules/home/dev.nix`. Fish/Nix (home-manager + NixOS via the dual module).

## 1. Objective

Fold today's three throwaway-shell functions — `ns` (ephemeral nix
packages), `sandbox` (isolated shell), `cowbox` (copy-on-write of the real
system) — into **one command, `ns`**, whose subject is always "spawn a
throwaway shell." The only thing that varies is **how the filesystem
behaves**; everything else (adding packages, running a one-shot command vs.
an interactive shell, cutting the network) composes on top of any mode.

`sandbox` and `cowbox` are **removed** once `ns` covers their behavior.

Target user: the repo owner, on the Kali workstation (primary) and the
NixOS hosts (secondary). Unprivileged; no root, no daemon.

## 2. Command surface

### Grammar
```
ns [MODE] [SIGIL] [pkg ...] [ -- | cmd ... ]
```
- **No trailing `--`** → the tokens after the mode are a command to run,
  then exit: `ns rg -n foo .` (first token doubles as the package).
- **Trailing `--`** → interactive shell; all preceding tokens are packages
  added to `PATH`: `ns rg fd --`.
- **MODE alone** (no pkgs, no cmd) → interactive shell in that world:
  `ns -i`, `ns -r`.

### Modes (how the filesystem behaves; default = your live system)
| Mode | Long / short / sigil | Sees real files | Writes persist | For |
|------|----------------------|:---:|:---:|-----|
| live (default) | *(none)* | yes | **yes** | grab a tool, do real work |
| isolated | `--isolated` / `-i` / `!` | **no** (empty `/work`) | no | run untrusted/unknown code, walled off |
| rehearse | `--rehearse` / `-r` / `@` | yes | **no** (copy-on-write) | rehearse a risky change on the real system |

Sigils `!` and `@` are safe as an unquoted first argument in fish (unlike
`~`, `#`, `%`, `^`, which fish would expand or eat — see §8). Only one mode
may be given at a time.

### Options (compose with any mode)
| Option | Meaning |
|--------|---------|
| `-N`, `--no-net` | cut the network inside the shell (applies to **isolated and rehearse**; live is always networked) |
| `URL` | `git clone --depth 1 URL` before entering — isolated: into `/work`; rehearse: into `./<repo>` in the cwd (reverts on exit). Not applicable to live. |
| `-h`, `--help` | print the banner |

### `-h` banner (canonical help text)
```
ns — throwaway shells. Spawn an ephemeral shell in one of three worlds.

USAGE
  ns [MODE] [pkg ...] [ -- | cmd ... ]

MODES  (how the filesystem behaves; default = your live system)
  -i, --isolated  (!)   WALLED  empty world; can't see or touch anything real
  -r, --rehearse  (@)   GHOST   your real files, but every change is discarded

PACKAGES & SHELL  (compose with any mode)
  ns rg fd --           interactive shell with rg + fd on PATH
  ns rg -n foo .        run one command, then exit
  ns -i                 (mode alone) → interactive shell in that world

OPTIONS
  -N, --no-net          cut off the network (isolated + rehearse)
  URL                   git-clone URL into the shell first (isolated/rehearse)
  -h, --help            show this

EXAMPLES
  ns jq --                      quick shell with jq
  ns -i https://github/x -N     clone a sketchy repo, isolated + offline
  ns -r just deploy             rehearse `just deploy`, then revert it all
```

### Worked examples
```
ns grep -ri foo .        live: run grep once, exit          (== today's ns)
ns grep ripgrep fd --    live: interactive shell w/ pkgs    (== today's ns …--)
ns !                     isolated scratch shell (sigil form of -i)
ns @ just deploy         rehearse `just deploy` (sigil form of -r)
ns -i                    isolated scratch shell
ns -i URL                isolated, cloned from URL
ns -i node --            isolated shell with node on PATH
ns -r                    copy-on-write shell (real fs, reverts)
ns -r rg fd --           cow shell + rg/fd on PATH
ns -r just deploy        run `just deploy` under cow, then revert everything
ns -r --no-net           cow shell with no network
```

## 3. Behavior per mode (implementation model)

- **live** — no bwrap. `nix shell nixpkgs#<pkgs>` exactly as today (run-cmd
  vs interactive `--`). This is the hot path and MUST stay byte-for-byte
  compatible with the current `ns`.
- **isolated** — bwrap: empty writable `/work` (a `mktemp -d`), read-only
  host system dirs, fresh `/proc`/`/dev`/`/tmp`, `HOME=/work`, a writable
  throwaway copy of `~/.config/fish` for the theme. `--unshare-all` +
  `--share-net` (or `--unshare-net` under `--no-net`). Trash `/work` on exit.
  (= today's `sandbox`.)
- **rehearse** — bwrap: per-top-level-directory `--tmp-overlay` (copy-on-write)
  for overlay-capable, submount-free dirs; `--ro-bind` for the rest (vfat
  `/boot`, dirs containing a nested mount); recreate root symlinks; fresh
  virtual mounts; real `/run` bound through. `--no-net` adds `--unshare-net`.
  (= today's `cowbox`.) Detection logic (fstype allow-list + submount
  predicate) is already validated on the host.
- **packages in isolated/rehearse** — reuse the live mechanism: wrap the
  bwrap call in `nix shell nixpkgs#$pkgs --command bwrap … fish`. `nix shell`
  resolves/fetches on the host and augments `PATH`; bwrap inherits that env;
  `/nix` is mounted inside so the binaries resolve — no nix/daemon/network
  needed *inside* the sandbox. Implementation must confirm the inner fish
  preserves the inherited `PATH`; fallback is to inject the resolved store
  `bin` dirs explicitly via `--setenv PATH`.
- **clone destination** — isolated: `/work/<repo>` (the writable scratch
  root). rehearse: `./<repo>` under the cwd, which reverts on exit like any
  other change. Both `cd` into the checkout.

## 4. Visual indicators (Tide theming)

The single `ns` function exports one marker into the mode shell,
`NS_MODE=live|isolated|rehearse` (plus an info string = package list / net
state). Because each mode is a fresh nested shell that re-sources `conf.d/`
(incl. the Tide theme) **before Tide bakes its prompt**, `NS_MODE`-conditional
overrides at the end of the theme reliably retint the prompt per mode. This
is per-shell and self-cleaning: exit → `NS_MODE` unset → normal theme.

**Guiding principle: normal shell = normal colors; only the sandbox modes
tint.** Live/day-to-day work is not recolored (it would be noise). The two
sandbox modes get a clear cue because that is exactly when a stray command
matters.

Per mode:
| Mode | Badge (right prompt) | Prompt accent (**Level 3**) |
|------|----------------------|-----------------------------|
| live | flask, coral `FF5D5D`, shows pkg list | none (normal prompt) |
| isolated (`!`) | cube, sand `D7AF5F` | `❯` + PWD segment → sand |
| rehearse (`@`) | recycle, violet `AF87FF` | `❯` + PWD segment → violet |

Level 3 = recolor the prompt **character** (`tide_character_color`) **and**
the **PWD segment background** (`tide_pwd_bg_color`) to the mode color; leave
git/status/etc. untouched so their meaning-carrying colors survive. When the
PWD background is tinted, also set `tide_pwd_color_{dirs,anchors,truncated_dirs}`
to **black `000000`** for contrast (both accent colors are light) — mirrors
how the badges use black text on these backgrounds.

Left-prompt chip: **no** (right badge + Level-3 tint is enough). The badge
style vars, `_tide_item_*` functions, and the `NS_MODE` accent overrides all
ship **inside the module**, gated on `tideBadges.enable`, so recipients get
the same experience; the marker is exported so it survives Tide's background
`fish -c` render child.

## 5. Discoverability — fish greeting one-liner

`fish_greeting` (in `fish.nix`) already prints a colored fuzzy-finder
cheatsheet line. Add a **second, concise, cleverly-colored one-liner** that
teaches the `ns` command at a glance, with each mode tinted to **match its
Tide badge color** so the greeting and the prompt reinforce each other:

- `ns` → nix blue (matches `tide_nix_shell` `7EBAE4`)
- `!`  → sand (`D7AF5F`, isolated badge)
- `@`  → violet (`AF87FF`, rehearse badge)
- `-h` → dim/grey

Proposed line (final wording tweakable):
```
📦  ns <pkg> run/shell · ! isolated · @ rehearse (reverts) · ns -h
```
Rendered via `set_color <hex>` around each colored token, matching the style
of the existing greeting `printf`. Keep it to one physical line; it must stay
readable at the `tide_prompt_min_cols` width.

## 6. Project structure

The feature is extracted into a **self-contained in-repo flake module** so it
can be shared (see §11). New folder `modules/dual/ns/`:

- `modules/dual/ns/ns.fish` — the entire implementation, pure fish: help banner,
  arg + sigil parsing, mode dispatch, bwrap logic for isolated/rehearse,
  `nix shell` for live. Self-detecting (`bwrap`/`findmnt`/`nix` presence).
- `modules/dual/ns/default.nix` — the dual (HM + NixOS) module. Options:
  `programs.ns.{enable, tideBadges.enable, extraPackages}`. Installs `ns.fish`
  as a fish function, pulls deps (`bubblewrap`, util-linux for `findmnt`,
  `git`), registers `ns` with the `browse_functions` whitelist, and — when
  `tideBadges.enable` — provides the badge vars, `_tide_item_*` functions, and
  the per-mode prompt accents (§4).
- `modules/dual/ns/README.md` — how to use `ns.fish` in an **arbitrary fish** with
  no Nix module (see §11).

Consumer-side changes in this repo:
- `flake.nix` — expose `homeManagerModules.ns` and `nixosModules.ns` from
  `modules/dual/ns`; import the module in this repo's profiles with
  `programs.ns.enable = true; programs.ns.tideBadges.enable = true;`.
- `modules/dual/fish.nix` — remove `ns`, `sandbox`, `cowbox` and their
  `_tide_item_*`; extend `fish_greeting` with the colored `ns` one-liner (§5,
  personal — stays here, not in the module).
- `modules/dual/fish_config/tide-theme.fish` — add the mode badge names to
  `tide_right_prompt_items` (layout is the consumer's choice).
- `modules/home/dev.nix` — drop `bubblewrap` (now pulled by the module).
- `docs/spec-ephemeral-shells.md` — this file.

## 7. Code style

- Match the existing `userFunctions` conventions: attribute-set entries keyed
  by function name; thorough multi-line comment above each explaining intent,
  mechanism, and non-obvious choices (see current `ns`/`sandbox`/`cowbox`).
- Argument parsing via fish `argparse` for `-i/-r/-N/-h` and long forms;
  detect sigils as leading positional tokens and normalize to the flags.
- `rg`/`fd` per repo rules; no bashisms; keep bwrap invocations readable
  (one `--flag` per line, as today).
- Icons set as raw Nerd Font glyphs (bytes), matching the other `tide_*_icon`
  lines.
- **Every package the module adds to a package list carries an inline comment
  stating what it provides and that it is for the `ns` command** — e.g.
  `bubblewrap # bwrap sandbox for the `ns` command (! isolated / @ rehearse)`,
  `util-linux # findmnt, used by `ns @` (rehearse) to enumerate mounts`,
  `git # `ns URL` clone`. This keeps the dependency's reason discoverable at
  the point it's declared.

## 8. Testing / verification strategy

- **Build gate**: every change verified with
  `nix build .#homeConfigurations.david.activationPackage --no-link` via a
  subagent (per `CLAUDE.md`), confirming the function derivations compile.
- **Behavioral gate** (host, unprivileged, via subagent): reuse the validated
  probes — isolated shell writes stay in `/work`; rehearse writes to `$HOME`
  and `/etc` revert on exit; live mode still runs a command and an
  interactive shell; `--no-net` actually removes network in both sandboxes;
  `-h` prints the banner; each mode lights the correct badge marker.
- **Compatibility gate**: `ns grep -ri foo .` and `ns grep fd --` behave
  exactly as before the refactor.

## 9. Boundaries

- **Always**: keep the live `ns <pkg>` path unchanged; keep the real
  `~/.config/fish` untouched (isolated copies it; rehearse overlays it
  read-through); trash all scratch state on exit.
- **Ask first**: before deleting the `sandbox`/`cowbox` functions if anything
  outside this module references them; before committing.
- **Never**: run bwrap as root or with raw block-device access; never bind
  the real filesystem writable in isolated/rehearse (would defeat the revert
  guarantee); never re-enable anything in the repo's root `SPEC.md`
  security boundaries.

## 10. Open questions to confirm

1. ~~Rehearse sigil~~ — **RESOLVED**: isolated `!`, rehearse `@`.
2. ~~Packages inside isolated/rehearse~~ — **RESOLVED**: include now, by
   wrapping bwrap in `nix shell … --command` (§3). Validate `PATH`
   propagation first during implementation.
3. ~~Badge marker~~ — **RESOLVED**: one exported `NS_MODE` var drives the
   badges and the Level-3 per-mode prompt accents (§4).
4. ~~`URL` clone~~ — **RESOLVED**: both modes. Isolated → `/work/<repo>`;
   rehearse → `./<repo>` in the cwd (reverts).

## 11. Distribution / packaging

- **Model B — in-repo flake module.** `modules/dual/ns/` is self-contained; the
  flake exposes `homeManagerModules.ns` and `nixosModules.ns`. A peer adds
  this repo as a flake input and imports one module:
  ```nix
  # their flake inputs: nsbox.url = "github:DSestu/NixConfig";
  # their home-manager / nixos config:
  imports = [ inputs.nsbox.homeManagerModules.ns ];
  programs.ns = {
    enable = true;
    tideBadges.enable = true;   # optional; off by default
    # extraPackages = [ pkgs.jq ]; # always on PATH in every mode (maybe, §10.2)
  };
  ```
  Splitting into its own repo later is a folder move; the module is already
  standalone.
- **`modules/dual/ns/README.md` — apply to an arbitrary fish (no Nix module).**
  Must document, in order:
  1. **Required packages** — an explicit list, each with what it's for and
     which mode needs it:
     | Package | Provides | Needed for |
     |---------|----------|------------|
     | `fish` | the shell | everything |
     | `bubblewrap` | `bwrap` | `!` isolated + `@` rehearse |
     | `util-linux` | `findmnt` | `@` rehearse (enumerate mounts) |
     | `git` | `git` | `URL` clone |
     | `coreutils` | `mktemp`,`cp`,`chmod`,`readlink`,`tail` | isolated setup (usually already present) |
     | `nix` | `nix shell` | live mode + packages inside any mode (optional otherwise) |
  2. Install: copy `ns.fish` into `~/.config/fish/functions/`.
  3. Kernel requirement: unprivileged overlayfs (~5.11+) for `@`/rehearse;
     note `!` and `@` work on any Linux, live-pkg mode needs Nix.
  4. Optional Tide theming by hand: which `tide_*` globals to set, the
     `_tide_item_*` functions, the `NS_MODE` accent overrides (§4), and how
     to add the items to `tide_right_prompt_items`.
- **Tide stays optional** throughout: with `tideBadges.enable = false` (and
  in a plain-fish install) the command is fully functional, just without the
  prompt theming.
