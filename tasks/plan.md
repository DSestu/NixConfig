---
title: NixConfig Remediation Plan
status: proposed
spec: ../SPEC.md
created: 2026-05-12
---

# NixConfig Remediation Plan

Companion to `SPEC.md`. Slices the five spec phases into atomic,
vertically-deployable tasks with explicit dependencies, acceptance
criteria, and verification commands. Each task lands as one commit (or
one stacked PR) so any single task is independently revertable.

## Dependency Graph

```
P1.1 delete dead code ──┐
P1.2 hypervisorModules ─┤
P1.3 line endings ──────┼──> P1.4 doc sync ──┐
                        │                     │
P2.1 SSH lockdown ──────┼─────────────────────┤
                        │                     │
P3.1 flip impermanence ─┘                     ├──> CHECKPOINT A
                                              │    (clean baseline)
                                              │
P4.1 preserveDirs option ──┐                  │
P4.2 wipe-root module ─────┤                  │
P4.3 disko btrfs layout ───┼──> P4.4 wire ───┼──> P4.5 verify ──> P4.6 re-enable
                                              │                    impermanence
                                              │                     │
                                              │                     ▼
                                              │                CHECKPOINT B
                                              │                (impermanence works
                                              │                 on bare-metal)
                                              │                     │
P5.1 identity binding ────────────────────────┘                     │
P5.2 extract mk-profile ───────────────────────────────────────────┤
P5.3 extract profiles ────── (depends on P5.2) ────────────────────┤
P5.4 _schema-detect helper ────────────────────────────────────────┤
P5.5 rename common→dual ──── (depends on P5.4) ────────────────────┤
P5.6 minor cleanups ────────────────────────────────────────────────┤
                                                                    │
                                                                    ▼
                                                              CHECKPOINT C
                                                              (refactors complete,
                                                               SPEC.md can be deleted)
```

**Parallelizable groups:**
- Phase 1 internal: P1.1, P1.2, P1.3 are independent; P1.4 needs them all.
- Phase 1 and Phase 2 are independent. Phase 3 only needs Phase 1.
- Phase 5 tasks are largely independent of each other except P5.2→P5.3 and P5.4→P5.5.

## Tasks

---

### P1.1 — Delete dead code

**Goal:** Remove three orphaned files. Nothing imports them; they all
reference removed modules.

**Files to delete:**
- `nixos/vm.nix`
- `nixos/platforms/vm-virtualbox.nix`
- `scripts/build-vbox-ova.sh`

**Touchpoints to verify:** `rg -n 'vm-virtualbox|vm\.nix|build-vbox-ova' --type=nix` returns zero matches before deletion (these files should be truly orphaned). If anything still references them, stop and reassess.

**Acceptance:**
- Three files removed.
- `rg -n 'impermanence-wipe' --type=nix` returns zero matches.
- Subagent runs `nix flake check --no-build` → succeeds.

**Risk:** Negligible. Pure delete.

---

### P1.2 — `hypervisorModules` becomes strict

**Goal:** Typos in profile `hypervisor` values fail eval instead of
silently producing a broken system.

**Edit:** `flake.nix` — the `hypervisorModules` `if/else if` chain.
- Remove the `virtualbox` branch (depends on P1.1).
- Replace the implicit `[]` fallthrough with `throw "unknown hypervisor: ${hv}"`.

**Acceptance:**
- Subagent runs `nix eval --impure --expr 'with (builtins.getFlake (toString ./.)).lib.evalModules { modules = []; }; true'` — irrelevant; instead:
- Subagent runs `nix flake check --no-build` → succeeds.
- Manual: temporarily edit a profile to `hypervisor = "nope"`; eval throws with a clear message; revert.

**Depends on:** P1.1 (so the `virtualbox` branch is gone first).

---

### P1.3 — Line-ending normalization

**Goal:** All `.nix`, `.sh`, `.md` are LF. New files stay LF.

**Steps:**
1. `git ls-files -z '*.nix' '*.sh' '*.md' | xargs -0 dos2unix` (or `sed -i 's/\r$//'`).
2. Add `.gitattributes`:
   ```
   *.nix text eol=lf
   *.sh  text eol=lf
   *.md  text eol=lf
   ```

**Acceptance:**
- `git grep -l $'\r' -- '*.nix' '*.sh' '*.md'` is empty.
- One commit, no logic changes — diff is whitespace-only.

**Risk:** Negligible. Pre-verify with `git diff --stat` shows no content changes.

---

### P1.4 — Doc sync (CONTRIBUTING.md + readme.md)

**Goal:** Documentation matches the post-refactor state.

**CONTRIBUTING.md edits:**
- Principle 3 (impermanence) — keep the principle; expand the mechanism paragraph to say "VM profiles use a tmpfs `/`; bare-metal profiles use a `wipe-root` initrd service on a btrfs subvol layout. Both produce the same outcome: a wiped `/` on every boot."
- Repository tree — remove `vm-virtualbox.nix`, `build-vbox-ova.sh`, `vm.nix`; add `nixos/modules/wipe-root.nix` (will exist after Phase 4 — flag with a TODO until P4.2 lands, or do this part of the doc sync at the end of Phase 4).
- All references to `impermanence-wipe.nix` → either remove or repoint.
- `preserveDirs` mentions stay (will be re-added in P4.1).

**readme.md edits:**
- Same: scrub `impermanence-wipe`, scrub VirtualBox/OVA path.

**Acceptance:**
- `rg -n 'impermanence-wipe|build-vbox-ova|vm-virtualbox' -- '*.md'` returns zero matches.
- The four mental-model principles read identically in spirit.

**Depends on:** P1.1, P1.2, P1.3.

**Note:** Some sentences will reference wipe-root/btrfs which doesn't exist until Phase 4. Two options:
- (a) Split: do dead-code/VBox scrub now; do the wipe-root mechanism docs as part of P4.4.
- (b) Single doc-sync at end of Phase 4.
Recommend (a) — keeps the doc honest at each checkpoint.

---

### P2.1 — Global SSH lockdown

**Goal:** Root SSH and password SSH are unconditionally off.

**Edit:** `nixos/base.nix`:
```nix
services.openssh.settings = {
  PermitRootLogin = "no";
  PasswordAuthentication = false;
  KbdInteractiveAuthentication = false;
};
```

**Cross-check:** `rg -n 'PermitRootLogin|PasswordAuthentication' --type=nix` — confirm no profile overrides. If any does, remove or justify.

**Acceptance:**
- Subagent: for each profile with `services.openssh.enable = true`, `nix eval .#nixosConfigurations.<name>.config.services.openssh.settings.PermitRootLogin` returns `"no"`.
- VM boot: `ssh -o PreferredAuthentications=password root@localhost -p 2222` fails immediately.
- VM boot: `ssh david@localhost -p 2222` with password rejects; with key, accepts.

**Risk:** If you currently SSH into any profile with password auth, that breaks. Confirm SSH-key setup before merging.

**Depends on:** none. Independent of Phase 1.

---

### P3.1 — Flip `impermanence = false` on bare-metal

**Goal:** Stop the profile from declaring something that isn't true.

**Edit:** `flake.nix` profiles table. Set `impermanence = false` on:
- `_template-bare-metal`
- `nixos-desktop`
- `nixos-vbox`

**Acceptance:**
- Subagent: `nix build .#nixosConfigurations.nixos-desktop.config.system.build.toplevel` succeeds.
- Subagent: `nix eval .#nixosConfigurations.nixos-desktop.config.profiles.impermanence.enable` returns `false`.
- `environment.persistence` and `restorePersistedShadow` no longer fire on those profiles.

**Depends on:** P1.* (clean baseline).

---

## ───── CHECKPOINT A — Clean Baseline ─────

Before proceeding to Phase 4, verify:
- [ ] All profiles eval (`nix flake check --no-build`)
- [ ] `nixos-vm` builds and boots (`./scripts/run-vm-gui.sh`)
- [ ] No CRLF in tree
- [ ] SSH lockdown applied
- [ ] No profile claims `impermanence = true` unless backed by a wipe mechanism
- [ ] CONTRIBUTING.md and readme.md scrubbed of VBox/wipe-module refs

Stop here and review if anything fails.

---

### P4.1 — Re-add `preserveDirs` option

**Goal:** Restore the typed option that `wipe-root.nix` and disko
layouts will read.

**Edit:** `nixos/modules/profile-options.nix`:
```nix
profiles.impermanence.preserveDirs = lib.mkOption {
  type = lib.types.listOf lib.types.str;
  default = [ "nix" "boot" ];
  description = "Top-level paths under / that survive wipe-root.";
};
```

**Acceptance:**
- `nix eval .#nixosConfigurations.nixos-vm.config.profiles.impermanence.preserveDirs` returns `[ "nix" "boot" ]`.
- No new build failures.

**Depends on:** Checkpoint A.

---

### P4.2 — `wipe-root.nix` module

**Goal:** Initrd service that wipes `/` (btrfs subvol rollback) on
every boot, leaving the preserve list intact.

**New file:** `nixos/modules/wipe-root.nix`.

**Mechanism (btrfs subvol rollback):**
- In initrd, mount the btrfs raw volume at a scratch mountpoint.
- Delete the `@root` subvolume.
- Re-create `@root` from a known-empty snapshot `@root-blank` taken at install time.
- Unmount; let stage-1 proceed.

**Constraints:**
- Module is *inert* unless `config.profiles.impermanence.enable = true` AND the platform is bare-metal. Use `lib.mkIf` and check `config.virtualisation.vmVariant == null` or a new `profiles.impermanence.strategy` enum (`"tmpfs"|"wipe-root"|null`).
- Recommendation: add `profiles.impermanence.strategy` to `profile-options.nix` in this task; default `"tmpfs"` for VMs, `"wipe-root"` for bare-metal. Set per-platform-module.

**Acceptance:**
- `nix eval` of the module on a bare-metal profile resolves without error.
- Build does not succeed yet end-to-end (depends on P4.3 disko layout).

**Depends on:** P4.1.

---

### P4.3 — Disko btrfs subvolume layout

**Goal:** `single-disk-uefi.nix` and `single-disk-bios.nix` describe a
btrfs filesystem with subvolumes `@root`, `@nix`, `@persist`, plus a
blank-root snapshot.

**Edit:** both disko layout files.

**Layout sketch:**
```
disk
└── partition
    └── btrfs
        ├── @root        → /        (wiped each boot)
        ├── @root-blank  → snapshot (template for rollback)
        ├── @nix         → /nix
        └── @persist     → /persist  (where environment.persistence reads from)
```

**Constraint:** keep the file usable for non-impermanent installs too —
gate the snapshot creation behind the same flag, or accept that the
extra subvolume is harmless when wipe-root is off.

**Acceptance:**
- Subagent: `nix build .#nixosConfigurations.nixos-desktop.config.system.build.toplevel` succeeds.
- `nix eval ...config.fileSystems."/".device` shows the btrfs subvol path.

**Depends on:** P4.1.

**Parallelizable with:** P4.2.

---

### P4.4 — Wire wipe-root into `mkProfile`

**Goal:** Bare-metal impermanence profiles automatically load
`wipe-root.nix`; VM profiles automatically load tmpfs-root via
`vm-qemu.nix`. The branching is mechanical, not duplicated.

**Edit:** `flake.nix` (or `nixos/lib/mk-profile.nix` if P5.2 has already
landed — see below for ordering note).

**Branching logic:**
- If `impermanence.enable && hypervisor == "qemu"` → vm-qemu handles tmpfs (already does).
- If `impermanence.enable && hypervisor == "none"` → load `wipe-root.nix` + ensure the host imports a disko layout from P4.3.

**Doc-sync followup:** Update CONTRIBUTING.md principle 3 mechanism
paragraph and tree diagram in *this* commit (the wipe-root file now
exists).

**Acceptance:**
- Subagent: `nix flake check --no-build` succeeds for the full flake.
- `nixos-vm` (qemu) still uses tmpfs; verify with `nix eval ...config.fileSystems."/".fsType` → `"tmpfs"`.
- `_template-bare-metal` with `impermanence = true` (temporarily for the test) evaluates and includes `wipe-root.nix` in its modules.

**Depends on:** P4.2, P4.3.

---

### P4.5 — Verify on `nixos-desktop`

**⚠ Destructive verification step. Backup before proceeding.**

**Goal:** Real-hardware verification that wipe-root + btrfs rollback
works end-to-end.

**Steps:**
1. Back up `/home`, `/etc`, anything not under `/persist` on the current `nixos-desktop`.
2. Re-install with the new disko layout (or migrate in place if comfortable).
3. Set `profiles.impermanence.enable = true` on `nixos-desktop` (still committed as `false`; do this in a worktree branch).
4. Reboot. Verify `/home/david` is empty except what `home.persistence` restored.
5. Touch a file at `/tmp/canary`. Reboot. Confirm gone.
6. Touch a file at `/persist/canary`. Reboot. Confirm survives.

**Acceptance:** Steps 4–6 all pass.

**Depends on:** P4.4. **Ask before running** — destructive.

---

### P4.6 — Re-enable `impermanence = true` on bare-metal profiles

**Goal:** Reverse P3.1 now that the mechanism exists.

**Edit:** `flake.nix`. Set `impermanence = true` on:
- `nixos-desktop`
- `nixos-vbox`

Leave `_template-bare-metal` at `false` with a comment: `# Enable after host-specific disko layout chosen.`

**Acceptance:**
- Both profiles build.
- The current-system closure on `nixos-desktop` includes `wipe-root.nix`.

**Depends on:** P4.5 verification passed.

---

## ───── CHECKPOINT B — Impermanence Works on Bare Metal ─────

- [ ] `nixos-desktop` boots with wipe-root, second-boot state matches expectation
- [ ] `nixos-vm` unchanged (tmpfs-root still working)
- [ ] CONTRIBUTING.md principle 3 expanded to cover both mechanisms

Stop and review. The remaining Phase 5 work is pure refactor and lower risk.

---

### P5.1 — Centralize identity

**Goal:** One source of truth for the user's identity.

**Edit:** `flake.nix`:
```nix
userIdentity = {
  name = "David";
  email = "davidsestu@sencrop.com";
};
```
Thread into `dev.nix` (git) and `fish.nix` (tailscale assertion) via
module args or by importing.

**Acceptance:**
- `rg davidsestu` returns only `flake.nix`.
- `nix build` of any profile succeeds.

**Depends on:** Checkpoint A (orthogonal to Phase 4).

---

### P5.2 — Extract `mkProfile` to `nixos/lib/mk-profile.nix`

**Goal:** `flake.nix` is a thin entrypoint.

**Edit:** Cut the `mkProfile` function from `flake.nix`; paste into
`nixos/lib/mk-profile.nix` as `{ self, nixpkgs, inputs, ... }: { name,
profile }: ...`. Import from `flake.nix`.

**Acceptance:**
- `flake.nix` shrinks by ~80 lines.
- `nix flake check --no-build` succeeds.
- All profile derivations are bit-identical (`nix path-info .#nixosConfigurations.<name>.config.system.build.toplevel` before/after).

**Depends on:** Checkpoint A. Better after Phase 4 to avoid touching
mk-profile twice.

---

### P5.3 — Extract profiles table to `nixos/profiles.nix`

**Goal:** Profile data lives in its own file.

**Edit:** Cut the `profiles = { ... }` attrset to `nixos/profiles.nix`;
import in `flake.nix`.

**Acceptance:**
- `flake.nix` shrinks again.
- Build outputs unchanged.

**Depends on:** P5.2.

---

### P5.4 — `_schema-detect.nix` helper

**Goal:** One implementation of HM-vs-NixOS schema detection.

**New file:** `modules/dual/_schema-detect.nix` (or
`modules/common/_schema-detect.nix` if P5.5 hasn't landed; rename in
P5.5):
```nix
{ options }:
{
  isHM     = options ? home;
  isNixOS  = options ? environment && options.environment ? systemPackages;
}
```

Consume in `fish.nix`, `network.nix`, `common.nix`.

**Acceptance:**
- `rg -n 'options \? home' --type=nix` returns matches only in `_schema-detect.nix`.
- All affected modules still produce the same evaluated config.

**Depends on:** Checkpoint A.

---

### P5.5 — Rename `modules/common/` → `modules/dual/`

**Goal:** Directory names match their semantics — `home/` (HM-only),
`nixos/` (NixOS-only), `dual/` (schema-detects).

**Steps:**
1. `git mv modules/common modules/dual`.
2. Update every import path referencing `modules/common/`.
3. Update CONTRIBUTING.md tree.

**Acceptance:**
- `rg -n 'modules/common' --type=nix` zero matches.
- `nix flake check --no-build` succeeds.

**Depends on:** P5.4.

---

### P5.6 — Minor cleanups (single commit)

**Goal:** Clear out the small uglies the review surfaced.

**Edits:**
- `modules/dev/claude-code.nix:147` — `toJSON = builtins.toJSON;` (drop eta-wrap).
- `modules/home/dev.nix:51` — switch `programs.git.settings` to documented `userName`/`userEmail`.
- `nixos/platforms/vm-qemu.nix:117` — `qemu.options = ["-vga" "virtio" "-display" "gtk,gl=on"];`.
- `modules/home/persistence.nix` — set `mode = "0700"` for `.config/gh`, `.config/google-chrome`, `.config/BraveSoftware`.

**Acceptance:**
- All profiles build.
- `rg -n 'data: builtins.toJSON data' --type=nix` returns zero matches.

**Depends on:** Checkpoint A. Independent of every other Phase 5 task.

---

## ───── CHECKPOINT C — Refactors Complete ─────

- [ ] `flake.nix` is < 100 lines and contains only inputs + outputs glue
- [ ] No `modules/common/` references remain
- [ ] All identity references centralize through one binding
- [ ] All minor cleanups landed
- [ ] `SPEC.md` and `tasks/` can be deleted (work is shipped)

---

## Verification Cheat Sheet

| What | Command | Where |
|---|---|---|
| All profiles eval | `nix flake check --no-build` | Subagent |
| One profile builds | `nix build .#nixosConfigurations.<name>.config.system.build.toplevel` | Subagent |
| VM boots | `./scripts/run-vm-gui.sh` | Foreground |
| Option value | `nix eval .#nixosConfigurations.<name>.config.<path>` | Inline (cheap) |
| Closure equality | `nix path-info .#... before vs after` | Subagent |
| Line endings | `git grep -l $'\r' -- '*.nix' '*.sh' '*.md'` | Inline |

Per `CLAUDE.md`: every `nix build` / `nix flake check` / `nixos-rebuild`
runs in a subagent, not the main conversation.
