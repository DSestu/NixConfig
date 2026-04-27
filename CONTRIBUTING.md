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
turns each profile into a `nixosSystem` by composing four ingredients:
the common baseline, the host folder, the platform module, and the
profile's extras.

**2. NixOS modules vs Home Manager modules are separate concerns.**
NixOS modules configure the *system* (services, kernel, bootloader,
filesystems). Home Manager modules configure the *user* (shell,
editors, dotfiles, user-level packages). A few modules need to work in
both contexts; they do that by guarding with `lib.optionalAttrs (options
? home)` / `lib.optionalAttrs (options ? environment ...)`. Don't
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
├── flake.nix                    # Profile dictionary + mkProfile
├── home.nix                     # User baseline (HM imports common modules)
├── readme.md                    # User-facing build/install/troubleshooting
├── CONTRIBUTING.md              # ← you are here
│
├── modules/                     # Home Manager modules + dual-context modules
│   ├── common.nix               # Dual-context: browsers etc.
│   ├── network.nix              # Dual-context: tailscale CLI + service
│   ├── deployment.nix           # HM: nixos-anywhere binary
│   ├── dev.nix                  # HM: editors, devenv, git, ssh
│   ├── fish.nix                 # HM: fish shell + theme + tools
│   ├── tide-theme.fish          # Tide prompt config sourced by fish.nix
│   ├── pentest.nix              # HM: nmap, bettercap, etc.
│   ├── gaming.nix               # Dual-context: Steam, GDLauncher
│   ├── persistence.nix          # HM: home.persistence (auto-added when impermanence on)
│   ├── kde-suite.nix            # NixOS: orchestrator for KDE
│   ├── kde/                     # NixOS + HM: split per-concern KDE config
│   │   ├── kde.nix
│   │   ├── plasma.nix
│   │   ├── plasma-appletsrc.nix
│   │   └── konsole.nix
│   └── wsl-home.nix             # HM overrides for WSL (no user systemd)
│
├── nixos/                       # NixOS-only stuff
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
│       │   └── default.nix
│       ├── nixos-desktop/
│       │   └── default.nix
│       ├── nixos-vbox/
│       │   ├── default.nix
│       │   └── hardware-configuration.nix
│       └── nixos-wsl/
│           └── fish.nix         # HM-side WSL fish bits (imported via flake)
│
└── configuration.nix            # Safety-net fail when invoked without --flake
```

## How `mkProfile` composes a system

In `flake.nix`, each profile is one entry in the `profiles` attrset:

```nix
nixos-desktop = sharedDesktopProfile // {
  hostname = "nixos-desktop";
  hypervisor = "none";
  extraHomeImports = [./modules/gaming.nix];
  impermanence = true;
};
```

`mkProfile name profile` is called for every entry and produces a
`nixpkgs.lib.nixosSystem`. It assembles the module list in this order:

1. **`commonNixosModules`** — the unconditional baseline:
   `profile-options.nix`, `nixos/base.nix`, the impermanence module,
   the home-manager module, and `disko.nixosModules.default`. Disko is
   inert here; it only activates if a later module sets
   `disko.devices`.

2. **`hostModules`** — auto-discovered from
   `nixos/hosts/<name>/default.nix` if that file exists. Drops in
   host-specific bootloader tweaks, hardware-config imports, and (for
   bare metal) the disko layout.

3. **`cfg.extraNixosModules`** — per-profile NixOS extras from the
   profile entry (e.g. `[./modules/kde-suite.nix]` from
   `sharedDesktopProfile`).

4. **`profileWiring`** — the glue that translates the profile entry
   into actual config: `networking.hostName`, the home-manager
   user-imports list (`commonHomeImports` + persistence module if
   impermanence is on + `cfg.extraHomeImports`), and the
   `profiles.impermanence.enable` flag.

5. **`hypervisorModules`** — selected by `cfg.hypervisor`. Maps `qemu`
   → `nixos/platforms/vm-qemu.nix`, `virtualbox` →
   `nixos/platforms/vm-virtualbox.nix`, `wsl` → `nixos-wsl.nixosModules.default`
   + `nixos/platforms/wsl.nix`, and `none` → no platform module
   (host folder + disko provide root FS and bootloader).

The same composition machine handles every target — there is no
special path for "the bare-metal one" or "the WSL one". Adding a new
hypervisor is a new branch in `hypervisorModules`; everything else
stays put.

## Where new things go (decision tree)

- *A user-level package* (CLI tool, editor, dotfile) → existing or new
  Home Manager module under `modules/`. Add an import in `home.nix` if
  it should be on every profile, or add it to one profile's
  `extraHomeImports` if it should be host-specific.

- *A system-level service* (systemd unit, kernel option, daemon) →
  NixOS module. If it's universal, drop it in `nixos/base.nix`. If
  it's only for graphical hosts, append to
  `sharedDesktopProfile.extraNixosModules`. If it's only for one host,
  put it in `nixos/hosts/<name>/default.nix`.

- *A package or service that has both a CLI and a daemon* (e.g.
  Tailscale: `tailscale` binary for the user, `tailscaled` for the
  system) → dual-context module under `modules/`, using
  `lib.optionalAttrs (options ? home)` / `lib.optionalAttrs (options ?
  services && options.services ? <name>)`. See `modules/network.nix`
  for the canonical pattern, `modules/common.nix` and
  `modules/gaming.nix` for the package-only variant.

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
3. Edit your *copy* of `default.nix` to flip UEFI ↔ BIOS, override the
   disk device, or add per-host kernel/bootloader tweaks. Leave the
   template files alone.
4. From WSL, run `nixos-anywhere --flake .#<your-host>
   --generate-hardware-config nixos-generate-config
   nixos/hosts/<your-host>/hardware-configuration.nix root@<target>`.
   The `pathExists` guard in your `default.nix` lets the flake
   evaluate before the hardware config exists; nixos-anywhere
   generates it on the target and writes it back to your repo.
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
  etc.) are in `modules/persistence.nix`'s
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

**`mkDefault` vs `mkForce`.** Layout / platform modules use
`mkDefault` so host folders can override without ceremony. Host
folders use `mkForce` only when overriding a layout module's
`mkDefault` would otherwise leave the option ambiguous (e.g.
`nixos-vbox/default.nix` forces GRUB-EFI over the layout's
systemd-boot default).

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
  `nixos/hosts/_template-bare-metal/default.nix`.
- *"Sandbox restricted-setting warning"* → `nix.settings.trusted-users`
  doesn't include your user on the host running the build. See
  `nixos/platforms/wsl.nix`.
- *"`nixos-rebuild` runs the wrong config in a QEMU VM"* → the 9p
  share isn't mounted at `/mnt/hmconfig`, or `/etc/nixos` symlink
  was wiped because `mnt` isn't in `preserveDirs`.
