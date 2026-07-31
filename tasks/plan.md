# Implementation plan — unified `ns` command

Contract: `docs/spec-ephemeral-shells.md` (status: complete). This plan slices
that spec into shippable, vertically-complete phases. **Read-only planning
artifact — no code has changed.**

## Components & dependency graph

```
        ┌─────────────────────────────┐
        │ A. ns.fish (pure fish core) │  parse/sigils/flags, -h banner,
        │    — the heart              │  mode dispatch, bwrap+nix logic
        └──────────────┬──────────────┘
                       │ installed by
        ┌──────────────▼──────────────┐
        │ B. modules/dual/ns/default.nix   │  dual module: options
        │    (dual HM+NixOS module)   │  {enable,tideBadges,extraPackages},
        └──────┬───────────────┬──────┘  deps (commented), discoverability
               │ exposed as    │ provides (gated)
   ┌───────────▼─────┐   ┌─────▼────────────────────┐
   │ C. flake outputs│   │ D. Tide theming          │
   │  homeManagerMod │   │  badges + Level-3 accents │
   │  nixosModules   │   │  driven by NS_MODE        │
   └───────────┬─────┘   └─────┬────────────────────┘
               │ imported by    │ prompt-item names added by
        ┌──────▼────────────────▼──────┐
        │ E. repo wiring                │  home.nix + commonNixosModules
        │    (consumer of the module)   │  enable module; tide_right_prompt_items;
        └──────────────┬────────────────┘  fish_greeting one-liner (personal)
                       │ replaces
        ┌──────────────▼──────────────┐
        │ F. removals                 │  old ns/sandbox/cowbox + their badges;
        │                             │  bubblewrap in dev.nix; old tide_* blocks
        └─────────────────────────────┘
        ┌─────────────────────────────┐
        │ G. modules/dual/ns/README.md     │  arbitrary-fish install + required pkgs
        └─────────────────────────────┘
```

Edges mean "depends on": everything hangs off **A (ns.fish)**. B installs A;
C exposes B; E consumes C; D and F layer on once modes exist; G documents the
finished behavior.

## Slicing strategy

Vertical, **by mode** — each phase delivers one complete user-visible path
(parse → dispatch → sandbox → exit/revert → verify), not a horizontal layer.
Live parity ships first (lowest risk, proves the module plumbing end-to-end),
then the two sandbox modes, then theming, then docs/polish. Tide theming is
deliberately deferred to Phase 4 so Phases 1–3 need not touch the prompt; the
old badges are left inert (they render nothing once their env vars are unset)
until Phase 4 replaces the whole scheme — so there is never a broken prompt.

## Phases & checkpoints

### Phase 1 — Module skeleton + live mode (parity)
Stand up `modules/dual/ns/{ns.fish,default.nix}`, expose flake outputs, import into
both consumer sites, and ship `ns.fish` with **arg/sigil/flag parsing**, the
**`-h` banner**, and the **live** mode (byte-for-byte behavior of today's
`ns`). Remove the old inline `ns` from `fish.nix` and solve discoverability.
- **Delivers:** `ns pkg args`, `ns pkg… --`, `ns`, `ns -h` — via the module.
- **Checkpoint 1:** home build green; `ns grep -ri foo .` and `ns rg fd --`
  behave exactly as before; `ns -h` prints the banner; `ns` still appears in
  ctrl+f (`browse_functions`). NixOS branch evaluates.

### Phase 2 — Isolated mode (`!` / `-i` / `--isolated`)
Port the validated `sandbox` logic into `ns.fish` as the isolated mode:
empty `/work`, read-only host, fresh virtual mounts, writable fish-config
copy, `--no-net`/`-N`, `URL`→`/work/<repo>`, and **package injection**
(`nix shell nixpkgs#$pkgs --command bwrap … fish`). Remove old `sandbox`.
- **First sub-step (de-risk):** validate `PATH` propagation of injected
  packages through bwrap into the inner fish; fall back to explicit
  `--setenv PATH` of resolved store `bin` dirs if needed.
- **Delivers:** `ns !`, `ns ! URL`, `ns ! -N`, `ns ! rg fd --`.
- **Checkpoint 2:** behavioral probe — isolated writes stay in `/work` and
  vanish on exit; `-N` removes network; clone lands in `/work`; injected
  packages are on `PATH` inside; theme renders.

### Phase 3 — Rehearse mode (`@` / `-r` / `--rehearse`)
Port the validated `cowbox` logic (per-top-level `--tmp-overlay`, submount +
fstype gating, ro-bind fallback, root symlinks, fresh virtuals, real `/run`)
as the rehearse mode; add `--no-net`, `URL`→`./<repo>` in cwd, and package
injection. Remove old `cowbox`.
- **Delivers:** `ns @`, `ns @ just deploy`, `ns @ URL`, `ns @ -N`, `ns @ rg --`.
- **Checkpoint 3:** behavioral probe — writes to `$HOME` and `/etc` revert on
  exit; `/boot` auto-ro-bound; `-N` removes network; injected packages work.

### Phase 4 — Tide theming (badges + Level-3 accents)
In the module (gated on `tideBadges.enable`): one exported `NS_MODE`
(+info) drives three badges (flask/cube/recycle) and the Level-3 accents
(`❯` + PWD bg recolored per mode, black PWD text for contrast). Wire the item
names into the consumer `tide_right_prompt_items`; remove the old
`tide_{ns,sandbox,cowbox}_*` blocks and `_tide_item_*` from `fish.nix`/theme.
- **Delivers:** live=normal+flask; `!`=sand tint+cube; `@`=violet tint+recycle.
- **Checkpoint 4:** in each mode the correct badge shows and `❯`+PWD take the
  mode color; live prompt unchanged; exiting restores normal theme.

### Phase 5 — Greeting, README, polish
Add the colored `ns` one-liner to `fish_greeting` (personal, in `fish.nix`);
write `modules/dual/ns/README.md` (required-packages table first, arbitrary-fish
install, kernel note, manual Tide setup); finalize `extraPackages` option;
ensure every added package carries its `# … for the ns command` comment.
- **Checkpoint 5:** full regression of all modes + flags; greeting renders;
  README instructions dry-checked; `sandbox`/`cowbox` fully gone; grep shows
  no dangling references.

## Verification method (every phase, per CLAUDE.md — via subagent)
- **Build gate:** `nix build .#homeConfigurations.david.activationPackage
  --no-link`; plus a NixOS-branch eval (`nix eval` of a profile option, or
  `nix flake check --no-build`) so the module's NixOS path is exercised.
- **Behavioral gate:** reuse the validated bwrap probes (writes revert / net
  cut / clone / PATH) run non-interactively inside the sandbox.
- **Compatibility gate:** live `ns` invocations match pre-refactor behavior.

## Risks & mitigations
1. **PATH propagation** for injected packages (Phase 2 first sub-step) —
   mitigated by explicit `--setenv PATH` fallback.
2. **ctrl+f discoverability** after `ns` leaves `userFunctions` — mitigate by
   giving `browse_functions` an extension point (modules append their function
   names to a shared fish global the picker reads), decided in Phase 1.
3. **NixOS vendor install** of `ns.fish` differs from HM — cover both in the
   dual module (mirror `userFunctionsSystemPkg` vs `programs.fish.functions`)
   and verify both branches.
4. **Intermediate prompt state** in Phases 1–3 — old badges left inert (no
   error) until Phase 4 replaces them; no broken prompt at any checkpoint.

## Out of scope (this plan)
- Committing (explicit user consent required).
- Splitting `modules/dual/ns/` into its own repo (folder move, later).
- Cloning into a live shell (spec: live has no `URL`).
