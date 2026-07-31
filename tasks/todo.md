# TODO — unified `ns` command

Contract: `docs/spec-ephemeral-shells.md` · Plan: `tasks/plan.md`
Verify each phase per CLAUDE.md (nix commands via subagent). Do not commit
without explicit consent.

## Phase 1 — Module skeleton + live mode ✅ (build+eval verified)
- [x] 1.1 Create `modules/dual/ns/ns.fish`: parsing, `-h` banner, **live**
      dispatch = today's `ns` (`NS_SHELL` preserved). Mode sigils `!`/`@`
      parsed; isolated/rehearse stubbed for Phase 2/3.
- [x] 1.2 Create `modules/dual/ns/default.nix` dual module (schema-detect):
      `options.programs.ns.{enable, tideBadges.enable, extraPackages}`; install
      `ns.fish` (HM `xdg.configFile`; NixOS `vendor_functions.d`); deps with
      per-package comments (bubblewrap/git/util-linux added ahead for P2/P3).
- [x] 1.3 Discoverability: `browse_functions` now also reads
      `$__user_browse_functions`; module ships a `10-ns-browse.fish` conf.d
      snippet appending `ns`.
- [x] 1.4 Flake: `homeManagerModules.ns` + `nixosModules.ns` → `./modules/dual/ns`.
- [x] 1.5 Wire consumer: imported in `home.nix` and `commonNixosModules`;
      `programs.ns.enable = true` in both.
- [x] 1.6 Remove old inline `ns` from `fish.nix` `userFunctions`.
- [x] **Checkpoint 1** — HM build green; NixOS eval `programs.ns.enable=true`;
      `ns.fish` + `10-ns-browse.fish` present in generation. **Human review.**

## Phase 2 — Isolated mode (`!` / `-i`)
- [x] 2.0 Spike: verify injected-package `PATH` propagation through bwrap into
      inner fish; note fallback (`--setenv PATH` of store `bin` dirs).
- [x] 2.1 Port `sandbox` logic into `ns.fish` isolated mode: empty `/work`,
      ro host dirs, fresh `/proc`/`/dev`/`/tmp`, writable fish-config copy,
      `HOME=/work`, `--unshare-all` + net toggle, export `NS_MODE=isolated`.
- [x] 2.2 `--no-net`/`-N` cuts network; `URL` → clone into `/work/<repo>`.
- [x] 2.3 Package injection: `nix shell nixpkgs#$pkgs --command bwrap … fish`.
- [x] 2.4 Add deps to module with comments: `bubblewrap`, `git`, `coreutils`.
- [x] 2.5 Remove old `sandbox` function from `fish.nix`.
- [x] **Checkpoint 2** — probe: isolated writes vanish; `-N` no network;
      clone in `/work`; `ns ! rg fd --` has rg/fd on PATH; theme renders.
      **Human review.**

## Phase 3 — Rehearse mode (`@` / `-r`)
- [x] 3.1 Port `cowbox` logic into `ns.fish` rehearse mode: per-top-level
      `--tmp-overlay`, fstype allow-list + submount predicate, ro-bind
      fallback, root symlinks, fresh virtuals, real `/run`; export
      `NS_MODE=rehearse`.
- [x] 3.2 `--no-net`/`-N`; `URL` → clone into `./<repo>` (reverts).
- [x] 3.3 Package injection (same mechanism as 2.3).
- [x] 3.4 Add `util-linux` (findmnt) to module deps with comment.
- [x] 3.5 Remove old `cowbox` function from `fish.nix`.
- [x] **Checkpoint 3** — probe: `$HOME` + `/etc` writes revert; `/boot`
      auto-ro-bound; `-N` no network; injected packages work. **Human review.**

## Phase 4 — Tide theming
- [x] 4.1 Module ships (gated on `tideBadges.enable`): `tide_*` badge vars for
      the 3 modes, `_tide_item_*` reading `NS_MODE`+info, and `NS_MODE`
      conditional Level-3 accents (`❯` + `tide_pwd_bg_color` per mode, black
      PWD text) appended to the theme.
- [x] 4.2 Consumer: add badge item names to `tide_right_prompt_items` in
      `tide-theme.fish`; set `programs.ns.tideBadges.enable = true`.
- [x] 4.3 Remove old `tide_{ns,sandbox,cowbox}_*` blocks + `_tide_item_*` and
      stale prompt-item entries from `fish.nix`/`tide-theme.fish`.
- [x] **Checkpoint 4** — each mode shows correct badge + `❯`/PWD tint; live
      unchanged; exit restores normal theme. **Human review.**

## Phase 5 — Greeting, README, polish
- [x] 5.1 Add colored `ns` one-liner to `fish_greeting` (spec §5), personal,
      in `fish.nix`.
- [x] 5.2 Write `modules/dual/ns/README.md`: required-packages table first, then
      arbitrary-fish install, kernel note, manual Tide setup (spec §11).
- [x] 5.3 Finalize `extraPackages` option (always-on-PATH tools).
- [x] 5.4 Audit: every module-added package has a `# … for the ns command`
      comment; `rg` finds no `sandbox`/`cowbox` references; `bubblewrap`
      removed from `dev.nix`.
- [x] **Checkpoint 5** — full regression of all modes/flags; greeting +
      README verified. **Human review.** (Commit only on explicit consent.)
