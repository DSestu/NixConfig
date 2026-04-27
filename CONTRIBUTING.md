# Contributing

This document explains the layout of the repo and the conceptual model
behind it. The README covers *what to run* (build commands, install
flows, troubleshooting); this document covers *where things go and
why*. Read this first if you're adding a profile, a module, a new
platform, or trying to understand why a given file lives where it does.

## Mental model

Four ideas drive every layout decision in this repo. Internalize these
and the directory tree explains itself.

**1. One flake, many profiles.** Every machine — VMs, bare-metal
desktops, WSL distros — is a *profile* in `flake.nix`. A profile is a
small attribute set (hostname, hypervisor, graphics yes/no,
impermanence yes/no, extra modules). A single helper, `mkProfile`,
turns each profile into a `nixosSystem` by composing five ingredients
(common NixOS baseline, common HM baseline, the host folder, the
impermanence flag, and the per-profile extras + platform module).

**2. NixOS modules vs Home Manager modules are separate concerns —
and the directory tree reflects that.** NixOS modules configure the
*system* (services, kernel, bootloader, filesystems). Home Manager
modules configure the *user* (shell, editors, dotfiles, user-level
packages). The split is enforced by the directory layout:
`modules/home/` for HM, `modules/nixos/` for NixOS, and the same
distinction inside each host folder (`nixos/hosts/<name>/home.nix` +
`./home/` for HM, `default.nix` + `./nixos/` for NixOS). Don't
collapse the split: the day you need to deploy a server profile
without graphics or a user account, the split is what saves you.

**3. Impermanence is a property of the running system, not a
filesystem.** On every boot, an initrd `wipe-root` service deletes
every top-level entry of `/` except a small preserve-list. Anything
the system needs across reboots lives under `/nix/persist` and is
bind-mounted back by the impermanence NixOS module. The Nix store and
the bootloader survive because they live under the preserved
directories (`nix`, `boot`). This means *any* root filesystem layout
works as long as `/nix` and `/boot` are on the preserved list — there
is no "impermanence filesystem", just a wipe service plus a list of
paths to mount back in.

**4. Disko is opt-in via the host folder, not via a flake flag.**
`disko.nixosModules.default` is loaded into every profile, but the
module is inert until something sets `config.disko.devices`. That only
happens when a host folder imports one of the layouts in
`nixos/disko/`. VM profiles don't import a disko layout (their root
comes from the platform module), so disko stays asleep. Bare-metal
profiles import a layout, so disko wakes up and owns partitioning +
`fileSystems.*`.

## Repository tree

```text
.
├── flake.nix                    # Profile dictionary + mkProfile (read this first)
├── home.nix                     # User baseline — imports every modules/home/*.nix
├── readme.md                    # User-facing build/install/troubleshooting
├── CONTRIBUTING.md              # ← you are here
│
├── modules/
│   ├── home/                    # Home Manager modules (every profile's user)
│   │   ├── common.nix           # Browsers etc.
│   │   ├── network.nix          # Tailscale CLI
│   │   ├── deployment.nix       # nixos-anywhere binary
│   │   ├── dev.nix              # editors, devenv, git, ssh
│   │   ├── fish.nix             # fish shell + theme + tools
│   │   ├── tide-theme.fish      # data file sourced by fish.nix
│   │   ├── pentest.nix          # nmap, bettercap, etc.
│   │   ├── gaming.nix           # Steam, GDLauncher
│   │   ├── persistence.nix      # home.persistence (auto-added when impermanence on)
│   │   └── wsl-home.nix         # HM overrides for WSL (no user systemd)
│   │
│   └── nixos/                   # NixOS modules (system-wide)
│       ├── kde-suite.nix        # Orchestrator: wires NixOS-side KDE + HM-side plasma config
│       └── kde/
│           ├── kde.nix
│           ├── plasma.nix
│           ├── plasma-appletsrc.nix
│           ├── konsole.nix
│           ├── konsole/         # color schemes referenced by konsole.nix
│           └── wallpapers/      # assets referenced by plasma.nix
│
├── nixos/                       # NixOS-only stuff that's NOT a reusable module
│   ├── base.nix                 # Common NixOS baseline (user, ssh, persistence map, …)
│   ├── modules/
│   │   ├── profile-options.nix  # Declares `profiles.impermanence.{enable,preserveDirs}`
│   │   └── impermanence-wipe.nix# initrd wipe-root service (the active one)
│   ├── platforms/               # Per-hypervisor wiring (root FS, bootloader)
│   │   ├── vm-qemu.nix          # QEMU vmVariant + 9p share
│   │   ├── vm-virtualbox.nix    # OVA build (virtualbox-image.nix)
│   │   └── wsl.nix              # NixOS-WSL plumbing
│   ├── disko/                   # Reusable disk layouts (opt-in via host folder)
│   │   ├── single-disk-uefi.nix # GPT + ESP + ext4 + systemd-boot
│   │   └── single-disk-bios.nix # GPT + BIOS-boot stub + ext4 + GRUB
│   └── hosts/                   # Per-profile host folders (auto-discovered)
│       ├── _template-bare-metal/# SKELETON — copy, don't edit
│       │   ├── default.nix      # NixOS-side host entry
│       │   ├── home.nix         # HM-side host entry
│       │   ├── nixos/           # NixOS sub-modules for this host (sub-folder)
│       │   └── home/            # HM sub-modules for this host (sub-folder)
│       ├── nixos-desktop/
│       │   └── default.nix
│       ├── nixos-vbox/
│       │   ├── default.nix
│       │   └── nixos/
│       │       └── hardware-configuration.nix
│       └── nixos-wsl/
│           ├── home.nix         # WSL profile is HM-only on the host side
│           └── home/
│               └── fish.nix
│
└── configuration.nix            # Safety-net fail when invoked without --flake
```

The naming convention `modules/<scope>/...` mirrors `nixos/hosts/<name>/<scope>/...`:
both use `home/` for Home Manager and `nixos/` for NixOS. When you're
trying to remember where a file goes, the answer is always "which
evaluator owns it, and is it shared across profiles or specific to one
host?".

## How `mkProfile` composes a system

In `flake.nix`, each profile is one entry in the `profiles` attrset:

```nix
nixos-desktop = sharedDesktopProfile // {
  hostname = "nixos-desktop";
  hypervisor = "none";
  extraHomeImports = [./modules/home/gaming.nix];
  impermanence = true;
};
```

`mkProfile name profile` is called for every entry and produces a
`nixpkgs.lib.nixosSystem`. It assembles the module list in this order:

1. **`commonNixosModules`** — the unconditional NixOS baseline:
   `profile-options.nix`, `nixos/base.nix`, the impermanence module,
   the home-manager module, and `disko.nixosModules.default`. Disko is
   inert here; it only activates if a later module sets
   `disko.devices`.

2. **`commonHomeImports`** — the unconditional HM baseline:
   `./home.nix`, which itself imports every file under `modules/home/`
   (browsers, fish, dev tools, network, etc.).

3. **Host folder (auto-discovered)** — for each profile, `mkProfile`
   probes `nixos/hosts/<name>/`:
   - `default.nix` is added to NixOS modules if it exists
   - `home.nix` is added to the HM imports if it exists

   Each can `imports = [./nixos/foo.nix]` or `imports = [./home/bar.nix]`
   to organize per-host sub-modules under the matching sub-folder.

4. **Impermanence wiring** — when the profile sets `impermanence =
   true`, `modules/home/persistence.nix` is appended to the user's HM
   imports automatically, and `profiles.impermanence.enable = true`
   flips on the wipe service.

5. **Per-profile extras + platform module:**
   - `cfg.extraNixosImports` — NixOS extras from the profile entry
     (e.g. `[./modules/nixos/kde-suite.nix]` from `sharedDesktopProfile`).
   - `cfg.extraHomeImports` — HM extras (e.g.
     `[./modules/home/gaming.nix]`).
   - `hypervisorModules` — selected by `cfg.hypervisor`. Maps `qemu`
     → `nixos/platforms/vm-qemu.nix`, `virtualbox` →
     `nixos/platforms/vm-virtualbox.nix`, `wsl` →
     `nixos-wsl.nixosModules.default + nixos/platforms/wsl.nix`, and
     `none` → no platform module (host folder + disko provide root FS
     and bootloader).

The same composition machine handles every target — there is no
special path for "the bare-metal one" or "the WSL one". Adding a new
hypervisor is a new branch in `hypervisorModules`; everything else
stays put.

## The per-profile recipe at a glance

A profile entry in the dictionary has up to six fields. Mandatory:

- `hostname` — string, becomes `networking.hostName`.
- `hypervisor` — `"qemu"` | `"virtualbox"` | `"wsl"` | `"none"`.
  Selects which platform module to load; `"none"` means bare metal
  (host folder + disko own the bootloader and root FS).

Optional (with defaults):

- `graphics` (default `true`) — only consumed by the QEMU platform
  module (toggles `-display gtk`).
- `impermanence` (default `false`) — flips the wipe-root service on
  and auto-adds `modules/home/persistence.nix` to the user's HM imports.
- `extraNixosImports` (default `[]`) — list of NixOS modules to append
  to the baseline.
- `extraHomeImports` (default `[]`) — list of HM modules to append to
  the user's imports.

`sharedDesktopProfile` is a convenience: a small attrset (`graphics =
true; extraNixosImports = [./modules/nixos/kde-suite.nix];`) merged
with `// { ... }` into every desktop profile. Override or extend it
per-profile by setting the same fields in the entry.

## Where new things go (decision tree)

- *A user-level package* (CLI tool, editor, dotfile) → existing or new
  module under `modules/home/`. Add an import in `home.nix` if it
  should be on every profile's user, or add it to one profile's
  `extraHomeImports` if it should be host-specific.

- *A system-level service* (systemd unit, kernel option, daemon) →
  module under `modules/nixos/`. If it's universal, drop it in
  `nixos/base.nix`. If it's only for graphical hosts, append to
  `sharedDesktopProfile.extraNixosImports`. If it's only for one host,
  put it in `nixos/hosts/<name>/default.nix` (or under
  `nixos/hosts/<name>/nixos/` and import from there).

- *A user-level package or service that only makes sense on one host*
  → drop a file under `nixos/hosts/<name>/home/` and import it from
  `nixos/hosts/<name>/home.nix`.

- *Per-host hardware quirks, kernel modules, microcode, bootloader
  tweaks* → drop a file under `nixos/hosts/<name>/nixos/` and import
  it from `nixos/hosts/<name>/default.nix`. `hardware-configuration.nix`
  follows the same pattern (lives at `<host>/nixos/hardware-configuration.nix`).

- *A new disk layout* (encrypted root, BTRFS subvolumes, separate
  `/home`, etc.) → new file in `nixos/disko/`. Keep impermanence
  compatibility in mind: top-level `nix` and `boot` (or whatever holds
  the bootloader) must end up on the wipe-root preserve list. Existing
  `single-disk-uefi.nix` and `single-disk-bios.nix` are the templates
  to follow.

- *A new hypervisor* → new file in `nixos/platforms/`, plus a new
  branch in `mkProfile`'s `hypervisorModules` `if/else if` chain. The
  platform module is responsible for `fileSystems."/"`,
  `boot.loader.*`, and any platform-specific quirks (9p shares,
  virtio drivers, EFI variables).

- *A new bare-metal target* → see "Adding a bare-metal profile" below.

## Adding a bare-metal profile

The full how-to is in `nixos/hosts/_template-bare-metal/default.nix`
and the matching block in `flake.nix`. The short version:

1. `cp -r nixos/hosts/_template-bare-metal nixos/hosts/<your-host>`.
2. Copy the `_template-bare-metal` block in `flake.nix` to a new key
   with the same name. Set `hostname = "<your-host>"`.
3. Edit your *copy* of `default.nix` (and optionally `home.nix`) to
   flip UEFI ↔ BIOS, override the disk device, or add per-host
   kernel/bootloader tweaks. Drop sub-modules under `./nixos/` (system)
   or `./home/` (user) and import them from the matching entry. Leave
   the template files alone.
4. From WSL, run `nixos-anywhere --flake .#<your-host>
   --generate-hardware-config nixos-generate-config
   nixos/hosts/<your-host>/nixos/hardware-configuration.nix
   root@<target>`. The `pathExists` guard in your `default.nix` lets
   the flake evaluate before the hardware config exists; nixos-anywhere
   generates it on the target and writes it back to your repo at the
   path you specified.
5. Commit `hardware-configuration.nix`. The guard flips and the file
   is auto-imported on subsequent rebuilds.

## Adding a VM profile

VM profiles don't need a host folder unless you want one — the
platform module (`vm-qemu.nix`, `vm-virtualbox.nix`) provides
`fileSystems."/"` and bootloader. Just add a profile entry to
`flake.nix`:

```nix
my-vm = sharedDesktopProfile // {
  hostname = "my-vm";
  hypervisor = "qemu";   # or "virtualbox"
  impermanence = true;   # or false
};
```

If you do create `nixos/hosts/<name>/default.nix`, **don't** import a
disko layout — the platform module already declares `fileSystems` and
the two would collide.

## The impermanence model

The wipe service lives in `nixos/modules/impermanence-wipe.nix`. It's
a single initrd-stage systemd unit:

- Runs after `sysroot.mount` (so `/` is visible at `/sysroot`) and
  before `initrd-root-fs.target` (so the wipe finishes before PID 1
  starts).
- Iterates `/sysroot/*`, skips active mount points, and `rm -rf`s
  anything not in `profiles.impermanence.preserveDirs`.
- The preserve list is a profile-level option declared in
  `nixos/modules/profile-options.nix`. Default is `["nix" "boot"
  "tmp"]`. Platform modules can append more (e.g. `vm-qemu.nix` adds
  `mnt` and `var` so 9p shares and the QEMU runtime survive the wipe).

The other half of the picture — what lives in `/nix/persist` and gets
bind-mounted back — is split:

- *System paths* (machine-id, SSH host keys, NetworkManager state,
  `/var/log`, etc.) are in `nixos/base.nix`'s
  `environment.persistence."/nix/persist"`.
- *User paths* (`.ssh`, browser profiles, `Documents`, IDE settings,
  etc.) are in `modules/home/persistence.nix`'s
  `home.persistence."/nix/persist"`. This module is auto-added to the
  user's HM imports by `mkProfile` whenever `impermanence = true`.

Two rules when editing the persistence map:

1. If you add a path that the system or user needs across reboots,
   add it to one of those two files — not to a new module.
2. If a new platform mounts something under `/` (a 9p share, a vfat
   partition, anything in `mountpoint -q` territory), append the
   top-level directory to that platform's
   `profiles.impermanence.preserveDirs` list. The wipe service skips
   active mount points, but only if the top-level entry survives the
   `case` filter.

Note: there is also an older `nixos/modules/wipe-root.nix` in the
tree. The active wipe service is `impermanence-wipe.nix`. Treat
`wipe-root.nix` as legacy until it's removed.

## The disko model

Two reusable layouts live in `nixos/disko/`:

- `single-disk-uefi.nix` — GPT, 512 MiB FAT32 ESP at `/boot`, ext4
  root, paired with systemd-boot.
- `single-disk-bios.nix` — GPT with a 1 MiB BIOS-boot partition for
  GRUB stage 2, ext4 root, no separate `/boot`.

Both:

- Use `lib.mkDefault` for the device name and bootloader settings, so
  a host folder can override without `lib.mkForce` gymnastics
  (`disko.devices.disk.main.device = "/dev/nvme0n1";`).
- Place the bootloader on a path that survives wipe-root's preserve
  list (`boot` for UEFI, `nix`/the GRUB partition for BIOS).
- Keep the layout flat — no LVM, no subvolumes, no swap — to match
  the QEMU/OVA platform modules.

A bare-metal host folder activates one of them with a single import:

```nix
imports = [
  ../../disko/single-disk-uefi.nix
  # ../../disko/single-disk-bios.nix
];
```

That's the whole opt-in. The flake input and `commonNixosModules`
entry are already in place.

## Conventions

**Profile naming.** `<distro-or-platform>-<role>` (`nixos-desktop`,
`nixos-vm-headless`, `nixos-wsl`). Leading underscore (`_template-...`)
means "skeleton — don't deploy this directly".

**Host folder naming.** Always matches the profile key exactly —
that's what `mkProfile` looks up via `./nixos/hosts + "/${name}"`.

**HM vs NixOS, everywhere.** The `home/` vs `nixos/` split shows up
in two places: at the top of `modules/`, and inside each host folder.
A file's directory tells you which evaluator loads it.

**`mkDefault` vs `mkForce`.** Layout / platform modules use
`mkDefault` so host folders can override without ceremony. Host
folders use `mkForce` only when overriding a layout module's
`mkDefault` would otherwise leave the option ambiguous (e.g.
`nixos-vbox/default.nix` forces GRUB-EFI over the layout's
systemd-boot default).

**`extraHomeImports` and `extraNixosImports`** are intentionally
named symmetrically. The pattern is "common baseline + per-profile
extras". If you find yourself wanting a third bucket, ask whether
the new thing belongs in the baseline (`commonNixosModules` /
`home.nix`) or in a host folder before adding a knob.

**Comment style.** Files that are non-obvious or set up
gotcha-prone behavior (the wipe service, the disko layouts, the
template, the WSL-home overrides) carry a top-of-file comment block
explaining *why*. New files in those categories should follow suit.
Trivial passthroughs don't need a header.

**Don't use `configuration.nix`.** The repo is flake-only. The
top-level `configuration.nix` exists solely to fail loudly if someone
runs `nixos-rebuild` without `--flake`. Don't put real config in it.

**Don't edit the templates.** `nixos/hosts/_template-bare-metal/` and
its companion entry in `flake.nix` are reference skeletons. Copy them
to a new name and edit the copy. The leading underscore and the
`REPLACE-ME` placeholder hostname are the visible signal.

**`--flake` everywhere.** All build/switch commands take
`--flake .#<profile-name>`. The `nix.nixPath` entry in `vm-qemu.nix`
is the one place that papers over the difference (so a guest VM can
still run plain `nixos-rebuild switch` against the shared 9p
checkout) — don't generalize that pattern.

## Where to look first when something breaks

- *"Profile evaluates fine but `nixos-rebuild` complains about
  `fileSystems`"* → the profile is bare-metal but the host folder
  doesn't import a disko layout, or it's a VM profile that
  accidentally does.
- *"Wipe killed something I needed"* → add the path to
  `environment.persistence` (system) or `home.persistence` (user), or
  add the top-level dir to `profiles.impermanence.preserveDirs` if
  it's a mount point.
- *"Hardware-config import errors on first install"* → the
  `pathExists` guard isn't there. Compare against
  `nixos/hosts/_template-bare-metal/default.nix`. Note that the
  hardware-config now lives at `<host>/nixos/hardware-configuration.nix`,
  not at the top of the host folder.
- *"Sandbox restricted-setting warning"* → `nix.settings.trusted-users`
  doesn't include your user on the host running the build. See
  `nixos/platforms/wsl.nix`.
- *"`nixos-rebuild` runs the wrong config in a QEMU VM"* → the 9p
  share isn't mounted at `/mnt/hmconfig`, or `/etc/nixos` symlink
  was wiped because `mnt` isn't in `preserveDirs`.
