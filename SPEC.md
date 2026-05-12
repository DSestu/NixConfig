---
name: NixConfig Post-Review Remediation Spec
status: draft
created: 2026-05-12
---

# NixConfig Post-Review Remediation

## 1. Objective

Resolve the drift between the May 7 tmpfs/impermanence refactor and the
rest of the repository, then carry out the refactors the review
identified. The end state matches the four-principle mental model in
CONTRIBUTING.md, with no dead code, no stale documentation, and no
profile whose `impermanence = true` is silently a lie.

Target user: solo maintainer (David). No backwards-compat constraints —
the only consumers of this flake are this repo's profiles.

## 2. Acceptance Criteria

A phase is "done" when:
- `nix flake check --no-build` passes
- For build-affecting changes, `nix build .#nixosConfigurations.<profile>.config.system.build.toplevel` succeeds for every profile the phase touches
- The boot path is verified end-to-end on at least one profile per phase (VM for VM-affecting phases; bare-metal manually for Phase 4)

## 3. Phases

### Phase 1 — Dead code & doc drift (low risk, mechanical)

Land first; unblocks everything else.

- **Delete `nixos/vm.nix`** — not imported, references non-existent `../modules/network.nix`, duplicates `nixos/platforms/vm-qemu.nix`.
- **Delete `nixos/platforms/vm-virtualbox.nix` and `scripts/build-vbox-ova.sh`** — no profile uses `hypervisor = "virtualbox"`; OVA path is abandoned.
- **Update the `hypervisor` enum site** in `flake.nix` (`hypervisorModules`) — remove the `virtualbox` branch; turn the fallthrough into an explicit `throw` so a typo fails eval.
- **Line-ending normalization** — convert all CRLF `.nix`/`.sh`/`.md` files to LF. Add `.gitattributes`:
  ```
  *.nix text eol=lf
  *.sh  text eol=lf
  *.md  text eol=lf
  ```
  Single commit, no logic changes.
- **Doc sync** — update `CONTRIBUTING.md` and `readme.md`:
  - Principle 3 in CONTRIBUTING.md (mental model) stays: impermanence is still a property of the running system, not a filesystem. The mechanism explanation expands to cover *both* strategies (tmpfs-root for VMs, wipe-root initrd for bare-metal) since Phase 4 will reinstate the latter.
  - Remove all references to the removed `impermanence-wipe.nix` module path; replace with current file locations.
  - Update the `preserveDirs` text to match the actual `environment.persistence` declarations.

**Acceptance:** `nix flake check --no-build` clean; `rg impermanence-wipe` returns zero matches; `file modules/**/*.nix` reports no CRLF.

### Phase 2 — SSH posture

Apply globally in `nixos/base.nix`:

```nix
services.openssh.settings = {
  PermitRootLogin = "no";
  PasswordAuthentication = false;
  KbdInteractiveAuthentication = false;
};
```

- Root SSH is **never** allowed, on any profile, regardless of `services.openssh.enable`.
- Remove or guard any per-profile override that re-enables either.
- `users.users.root.initialPassword` may stay (console/sudo only); document its scope inline.
- `users.users.david.initialPassword = "nixos"` stays for console but SSH-key-only is enforced for network access.

**Acceptance:** `nix eval .#nixosConfigurations.nixos-vm.config.services.openssh.settings.PermitRootLogin` returns `"no"` for every profile that enables `openssh`.

### Phase 3 — Bare-metal `impermanence = true` is currently a lie

Until Phase 4 lands, flip the flag to `false` on:
- `_template-bare-metal`
- `nixos-desktop`
- `nixos-vbox`

Single commit, isolated from Phase 4. This makes the current behavior match the declaration.

**Acceptance:** No profile claims `impermanence = true` unless its platform module actually wipes `/` on boot.

### Phase 4 — Bare-metal impermanence: wipe-root initrd

Reintroduce the canonical impermanence pattern for disk-backed roots.
This is the "real" fix.

**Design:**
- New module `nixos/modules/wipe-root.nix` provides an initrd service that wipes every top-level entry of `/` *except* a preserve list (`nix`, `boot`, `tmp`, plus anything the host adds via `profiles.impermanence.preserveDirs`).
- Re-add `preserveDirs` as a declared option in `nixos/modules/profile-options.nix` (currently the comments in the disko layouts mention it but it does not exist).
- Wipe runs in stage1, before stage2 activation, before `local-fs.target`.
- Default disko strategy: **btrfs subvolume rollback** on `single-disk-uefi.nix` and `single-disk-bios.nix`. Layout: one btrfs filesystem with `@root` (wiped → snapshotted blank-root rolled back) and `@nix`, `@persist` subvolumes preserved.
  - Rationale: simplest disko change, no second partition, works with the existing single-disk layouts. Avoids ZFS dependency.
- `vm-qemu.nix` stays on tmpfs-root (correct for ephemeral VMs); `wipe-root.nix` is not loaded there.
- The `profiles.impermanence.enable = true` flag now branches inside `mkProfile`: VM hypervisors get the tmpfs-root path, bare-metal gets `wipe-root.nix` + the disko btrfs layout.

**Re-enable `impermanence = true`** on `nixos-desktop` and `nixos-vbox` once verified. `_template-bare-metal` stays as a template — leave `impermanence = false` with a `# Enable after disko layout chosen` comment.

**Acceptance:** Boot `nixos-desktop` twice; on second boot, `/home/david` is empty except for what `home.persistence` restored; `/var/log` retained via `environment.persistence`; `/nix/store` untouched.

### Phase 5 — Refactors (carry CONTRIBUTING.md's spirit forward)

Each refactor is one commit. CONTRIBUTING.md's four principles are
load-bearing; preserve their wording, only update the file/function
names they reference.

1. **Centralize identity** — one `let` binding in `flake.nix`:
   ```nix
   userIdentity = { name = "David"; email = "davidsestu@sencrop.com"; };
   ```
   Threaded into `dev.nix` (git config) and `fish.nix` (tailscale assertion). Single source of truth.
2. **Extract `mkProfile` + profiles table** — move out of `flake.nix`:
   - `nixos/lib/mk-profile.nix` — the function
   - `nixos/profiles.nix` — the attrset of profiles
   `flake.nix` becomes a thin entrypoint (~80 lines). Principle 1 ("one flake, many profiles") is unchanged in spirit; just lives in two files now.
3. **Unify dual-schema detection** — `modules/common/_schema-detect.nix` returns `{ isHM, isNixOS }`. Consumed by `fish.nix`, `network.nix`, `common.nix` (and any future dual-schema module). Principle 2 (HM vs NixOS separate) is unchanged; this just deduplicates the bridge.
4. **Move dual-schema modules out of `modules/common/`** — rename `modules/common/` → `modules/dual/` to make the boundary explicit. `modules/home/` and `modules/nixos/` are pure; `modules/dual/` is "lives in both, schema-detects". Update CONTRIBUTING.md tree.
5. **Minor cleanups uncovered in review:**
   - `claude-code.nix:147` — drop the eta-wrap `toJSON = data: builtins.toJSON data` → `toJSON = builtins.toJSON`.
   - `dev.nix:51` — switch `programs.git.settings` to documented `programs.git.userName`/`userEmail`.
   - `vm-qemu.nix:117` — split `qemu.options` into one token per element.
   - `vm-qemu.nix` tmpfs `size=2G` — keep at 2G for now (VM has 8G RAM, KDE plus builds fit); revisit if OOMs appear.
   - Persisted user-data dirs (`.config/gh`, `.config/google-chrome`, `.config/BraveSoftware`) — set `mode = "0700"` in `modules/home/persistence.nix`.

## 4. Project Structure (post-refactor)

```text
.
├── flake.nix                    # Thin entrypoint: inputs, outputs, overlay glue
├── home.nix
├── configuration.nix
├── readme.md
├── CONTRIBUTING.md              # Same four principles, updated file refs
├── SPEC.md                      # ← this file (delete after Phase 5 lands)
├── CLAUDE.md                    # Project conventions for Claude Code
├── .gitattributes               # LF line endings
│
├── nixos/
│   ├── profiles.nix             # Profile attrset (was in flake.nix)
│   ├── lib/
│   │   └── mk-profile.nix       # mkProfile function (was in flake.nix)
│   ├── base.nix                 # System-wide baseline (incl. global SSH lockdown)
│   ├── modules/
│   │   ├── profile-options.nix  # profiles.impermanence.{enable,preserveDirs}
│   │   └── wipe-root.nix        # Bare-metal wipe-root initrd service
│   ├── platforms/
│   │   ├── vm-qemu.nix          # tmpfs-root path for VMs
│   │   └── wsl.nix
│   ├── disko/
│   │   ├── single-disk-uefi.nix # btrfs subvols supporting wipe-root
│   │   └── single-disk-bios.nix
│   └── hosts/<name>/{default.nix, home.nix, nixos/, home/}
│
└── modules/
    ├── home/                    # HM-only modules
    ├── nixos/                   # NixOS-only modules
    └── dual/                    # Dual-schema (was `common/`)
        └── _schema-detect.nix
```

## 5. Code Style

Existing conventions, made explicit:

- LF line endings everywhere.
- 2-space indentation in `.nix` (alejandra-compatible).
- Module signatures: `{ config, lib, pkgs, ... }:` — always include `lib` even if unused locally; the bootstrap module shouldn't be the only one that forgets it.
- Conditional module bodies: prefer `lib.mkIf cond { ... }` over `if cond then { ... } else { }`. Already the pattern in `vm-qemu.nix`; apply consistently.
- Comments explain *why*, not *what*. The current `vm-qemu.nix` block comments (bootstrap rationale, msize rationale) are the model.
- No dead code, no `# removed` markers, no backwards-compat shims.

## 6. Testing Strategy

This is a personal Nix flake — no automated test suite, but every phase
has a cheap verification:

| Check | Phase | Command |
|---|---|---|
| Eval correctness | All | `nix flake check --no-build` |
| Profile builds | All build-affecting | `nix build .#nixosConfigurations.<name>.config.system.build.toplevel` |
| VM boot | Any change touching `vm-qemu.nix`, `base.nix`, `wipe-root.nix` | `./scripts/run-vm-gui.sh`, log in as david, verify shell + persistence |
| Bare-metal boot | Phase 4 only | Manual on `nixos-desktop` after backup |
| SSH posture | Phase 2 | `nix eval ...config.services.openssh.settings` for each profile with openssh enabled |
| Line endings | Phase 1 | `git grep -l $'\r' -- '*.nix' '*.sh' '*.md'` returns empty |

**Run nix commands via subagent** — see `CLAUDE.md`. `nix build` and
`nix flake check` produce hundreds of lines; running them in the main
context burns the budget for the next phase.

## 7. Boundaries

**Always:**
- Run `nix build` / `nix flake check` / `nixos-rebuild` via a temporary subagent (see CLAUDE.md).
- Preserve the four mental-model principles in CONTRIBUTING.md. Update the *referents* (file names, mechanism details), not the principles themselves.
- `mkIf cond` gate every block of impermanence-specific config — VMs shouldn't load bare-metal wipe-root, bare-metal shouldn't load tmpfs-root.
- Land each phase as its own commit (or stacked PR) so a single phase can be reverted.

**Ask first:**
- Before touching `nixos-desktop` in a way that requires a real reboot to verify (Phase 4 in particular — destructive root wipe needs a backup confirmation).
- Before deleting any file or option that *could* be in use externally (this flake has no external consumers, but ask anyway if something looks load-bearing).
- Before changing the four principles of CONTRIBUTING.md (mechanism details under a principle are fair game; the principles themselves are not).

**Never:**
- Re-enable root SSH login, on any profile, for any reason.
- Re-enable SSH password authentication.
- Use `--no-verify` on commits.
- `git reset --hard` / force-push without explicit ask.
- Add an `impermanence = true` profile without verifying the wipe mechanism actually fires (otherwise we recreate the exact bug this spec exists to fix).
- Pollute the main conversation context by running long nix builds directly. Delegate.
