# NixConfig Remediation — TODO

See `plan.md` for full task details. See `../SPEC.md` for context.

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done · `[!]` blocked

## Phase 1 — Clean baseline

- [x] **P1.1** Delete `nixos/vm.nix`, `scripts/build-vbox-ova.sh` *(vm-virtualbox.nix moved to P1.2 — atomic with flake.nix edit)*
- [x] **P1.2** Make `hypervisorModules` strict (drop `virtualbox`, `throw` on unknown) + delete `nixos/platforms/vm-virtualbox.nix`
- [x] **P1.3** Normalize line endings to LF + add `.gitattributes`
- [x] **P1.4** Doc sync: scrub `impermanence-wipe` / VBox refs from CONTRIBUTING.md + readme.md
      *(wipe-root mechanism docs deferred to P4.4)*

## Phase 2 — SSH

- [x] **P2.1** Global SSH lockdown in `nixos/base.nix` (no root, no passwords)

## Phase 3 — Honest impermanence flag

- [x] **P3.1** Flip `impermanence = false` on `_template-bare-metal`, `nixos-desktop`, `nixos-vbox`

### ───── Checkpoint A: clean baseline ─────

- [x] `nix flake check --no-build` clean *(nixos-desktop now builds; nixos-vm toplevel "missing root fs" is the documented vmVariant artifact, not a real failure — use `system.build.vm` for VMs)*
- [~] VM still boots *(user verifies — `./scripts/run-vm-gui.sh` / `run-vm-headless.sh`)*
- [x] No CRLF in tree
- [x] No false `impermanence = true` claims *(every profile's impermanence flag matches a working mechanism)*

## Phase 4 — Bare-metal wipe-root impermanence

- [-] **P4.1** ~~Re-add `profiles.impermanence.preserveDirs` option~~ *(skipped — under btrfs subvol rollback the preserve list is structural, not runtime; no option needed)*
- [x] **P4.2** New `nixos/modules/wipe-root.nix` (initrd btrfs subvol rollback)
- [x] **P4.3** Btrfs subvol layout in `single-disk-uefi.nix` *(P4.3b: `single-disk-bios.nix` deferred — not currently consumed by any profile)*
- [x] **P4.4** Wire wipe-root vs tmpfs branching into `mkProfile` *(CONTRIBUTING.md mechanism para already done in P1.4)*
- [~] **P4.5a** Disko image builds successfully (`main.raw`, 20G sparse, cached). Awaiting manual qemu boot to exercise wipe-root behavior.
- [ ] **P4.5b** ⚠ Destructive: verify on real `nixos-desktop` hardware *(ask before running)*
- [x] **P4.6** ~Re-enable `impermanence = true` on `nixos-desktop` + `nixos-vbox`~ *(nixos-desktop already true via user edit; nixos-vbox still false pending verification)*

### ───── Checkpoint B: bare-metal impermanence works ─────

- [ ] Desktop wipes on boot, persistence restores correctly
- [ ] VM unchanged

## Phase 5 — Refactors

- [x] **P5.1** Centralize identity in `modules/_user-identity.nix` (chose file-import over flake.nix let-binding to work cleanly with dual-schema fish.nix)
- [x] **P5.2** Extract `mkProfile` → `nixos/lib/mk-profile.nix`
- [x] **P5.3** Extract profiles table → `nixos/profiles.nix`
- [x] **P5.4** Create `_schema-detect.nix`; consume in fish/network/common
- [x] **P5.5** Rename `modules/common/` → `modules/dual/`
- [x] **P5.6** Minor cleanups: `toJSON` eta-wrap, qemu.options tokens, persistence file modes *(git `settings` left alone — `userName`/`userEmail` are now the HM-deprecated form)*

### ───── Checkpoint C: refactors complete ─────

- [~] `flake.nix` < 100 lines *(landed at 132 — soft target; further shrink would just chop the comment block and the code-cursor overlay, both load-bearing)*
- [x] No `modules/common/` references
- [x] Identity centralized
- [ ] Delete `SPEC.md` + `tasks/` *(user's call — leave for history or delete now)*

## Notes

- Per `CLAUDE.md`: every `nix build`, `nix flake check`, `nixos-rebuild` runs in a subagent.
- One commit per task; revert-safe.
- Stop at each checkpoint for review.
