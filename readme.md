# Home Manager + NixOS Flake

## Daily commands

### Update packages

```bash
nix flake update nixpkgs
```

### Garbage collect

```bash
nix-collect-garbage -d
```

### Export plasma settings

```bash
nix run github:nix-community/plasma-manager
```

### Refresh AppImage hash

Compute latest SRI hash:

```bash
./scripts/update-appimage-hash.sh "https://example.com/MyApp-x86_64.AppImage"
```

Compute and replace an existing hash in a file:

```bash
./scripts/update-appimage-hash.sh "https://example.com/MyApp-x86_64.AppImage" --replace modules/gaming.nix "sha256-OLD_HASH"
```

## VM workflows

VM targets reuse the same base machine configuration as real-machine targets; only hypervisor-specific modules differ.

### QEMU GUI

Grab keyboard with `ctrl + alt + g`.

```bash
./scripts/run-vm-gui.sh
```

### QEMU headless

```bash
./scripts/run-vm-headless.sh
```

### VirtualBox image (OVA)

```bash
./scripts/build-vbox-ova.sh
```

Import the generated `*.ova` from `./result/` into VirtualBox, then start it from the VirtualBox UI.

### VirtualBox shared folder (repo on host)

Add the repo as a shared folder from the host (Windows PowerShell/CMD):

```bash
VBoxManage sharedfolder add "nixos-vbox" --name "nixconfig" --hostpath "D:\projets_python_ssd\Sencrop\NixConfig" --automount
```

Inside the NixOS guest:

```bash
sudo mkdir -p /mnt/nixconfig
sudo mount -t vboxsf -o uid=$(id -u),gid=$(id -g),dmode=775,fmode=664 nixconfig /mnt/nixconfig
ls /mnt/nixconfig
```

If your user cannot access the mount:

```bash
sudo usermod -aG vboxsf $USER
```

Then log out/in (or reboot).

Optional: make the mount persistent for the `nixos-vbox` profile by adding this to
`nixos/hosts/nixos-vbox/default.nix`:

```nix
fileSystems."/mnt/nixconfig" = {
  device = "nixconfig";
  fsType = "vboxsf";
  options = [ "rw" "uid=1000" "gid=100" "dmode=0775" "fmode=0664" ];
};
```

If unmount fails with "target is busy", leave the folder and use lazy unmount:

```bash
cd ~
sudo umount -l /mnt/nixconfig
sudo mount -t vboxsf -o uid=$(id -u),gid=$(id -g),dmode=775,fmode=664 nixconfig /mnt/nixconfig
```

If `lsof` is available, you can inspect active users before unmounting:

```bash
sudo lsof +D /mnt/nixconfig
```

### Rebuild inside VM

```bash
nixos-rebuild build --flake .#nixos-vbox
sudo ./result/bin/switch-to-configuration switch
```

## Remote deployment

### Local -> remote update (`nixos-rebuild`)

Run from this repo on your local machine:

```bash
sudo nixos-rebuild switch --flake .#<profile-name> --target-host <user>@<remote-host> --use-remote-sudo
```

Example:

```bash
sudo nixos-rebuild switch --flake .#nixos-vm --target-host david@192.168.1.50 --use-remote-sudo
```

Optional pre-check build:

```bash
sudo nixos-rebuild build --flake .#<profile-name> --target-host <user>@<remote-host> --use-remote-sudo
```

### Remote install/reprovision (`nixos-anywhere`)

Use this for first install or full reprovision over SSH.

WARNING: destructive by default (can repartition/reinstall the target).

```bash
nixos-anywhere --flake .#<profile-name> <user>@<remote-host>
```

Example:

```bash
nixos-anywhere --flake .#nixos-vm root@192.168.1.50
```

Fallback via `nix run`:

```bash
nix run github:nix-community/nixos-anywhere -- --flake .#<profile-name> <user>@<remote-host>
```

## Per-profile host configuration

Each profile can have a matching folder at `nixos/hosts/<profile-name>/`.
If a `default.nix` exists there, `mkProfile` imports it automatically — no
flake edits required. This is the place for host-specific modules that
don't belong in the shared tree (hardware quirks, bootloader overrides,
partitions, filesystems, custom kernel params, etc.).

Layout:

```text
nixos/hosts/
  nixos-desktop/
    default.nix              # auto-imported for `nixos-desktop`
    hardware-configuration.nix  # generated on the target, see below
```

VM profiles don't need a host folder — their bootloader/filesystems come
from `nixos/platforms/vm-qemu.nix` or `nixos/platforms/vm-virtualbox.nix`.

### Bare-metal: generating `hardware-configuration.nix`

Bare-metal profiles (`hypervisor = "none"`) need a per-host
`hardware-configuration.nix` with the machine's root-FS identifier,
kernel modules, CPU microcode, and bootloader device. That file cannot
be known ahead of time; it must be generated on the target.

1. Boot the target from a NixOS install ISO, partition/format, and mount
   the root at `/mnt` (or SSH into an already-running NixOS install).

2. Generate the hardware config:

   ```bash
   # during install
   sudo nixos-generate-config --root /mnt --show-hardware-config

   # or on a running system
   sudo nixos-generate-config --show-hardware-config
   ```

3. Redirect the output into the host folder on your workstation and
   commit it:

   ```bash
   ssh <user>@<remote> 'sudo nixos-generate-config --show-hardware-config' \
     > nixos/hosts/<profile-name>/hardware-configuration.nix
   git add nixos/hosts/<profile-name>/hardware-configuration.nix
   git commit -m "Add hardware-configuration.nix for <profile-name>"
   ```

4. Rebuild — locally to validate, then remotely to apply:

   ```bash
   nix eval ".#nixosConfigurations.<profile-name>.config.system.build.toplevel.drvPath"
   sudo nixos-rebuild switch --flake .#<profile-name> \
     --target-host <user>@<remote> --use-remote-sudo
   ```

The `default.nix` in each host folder guards the hardware-config import
with `builtins.pathExists`, so the flake keeps evaluating before the
file has been produced (bare-metal profiles will still fail at build
time with a clear `fileSystems`/`boot.loader` assertion — that's the
signal to run step 2).

## Performance notes

### KVM acceleration

Without KVM, VM performance is typically 10-20x slower.

Check membership:

```bash
groups | grep -q kvm && echo "KVM enabled" || echo "You need to join the kvm group"
```

If needed:

```bash
sudo usermod -aG kvm david
```

Then log out and back in.

## Adding a new module

This repo supports:

- Home Manager-only modules (user config/packages)
- NixOS-only modules (system services/kernel/networking)
- Shared modules imported by both (with option guards, see `modules/common.nix`)

The mental model is minimal: every profile gets a fixed baseline, and each
profile can append its own extras via two lists — `extraNixosModules` and
`extraHomeImports`. There are no flags or toggles.

### 1) Create module file

```bash
mkdir -p modules
micro modules/example.nix
```

Minimal Home Manager module:

```nix
{
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    hello
  ];
}
```

### 2) Wire module

Decide where it should live:

- Everywhere (baseline for all profiles):
  - Home Manager: add `./modules/example.nix` to `imports` in `home.nix`.
  - NixOS: add `./modules/example.nix` to `commonNixosModules` in `flake.nix`.
- On every desktop profile (QEMU/VirtualBox/bare-metal desktop):
  - NixOS-style: append to `sharedDesktopProfile.extraNixosModules`.
  - (Home Manager-style: `sharedDesktopProfile` does not hold HM extras by
    default — either add one there or add it per profile below.)
- On a single profile only:
  - Home Manager-style: set `extraHomeImports = [...]` on `profiles.<name>`.
  - NixOS-style: set `extraNixosModules = [...]` on `profiles.<name>` (this
    replaces the list inherited from `sharedDesktopProfile`; concatenate
    `sharedDesktopProfile.extraNixosModules ++ [...]` if you want to keep
    the desktop defaults).

Example — add `./modules/example.nix` only to `nixos-desktop` as a Home
Manager import:

```nix
nixos-desktop = sharedDesktopProfile // {
  hostname = "nixos-desktop";
  hypervisor = "none";
  extraHomeImports = [./modules/example.nix];
};
```

### 3) Validate

```bash
home-manager switch --flake .#david
sudo nixos-rebuild switch --flake .#nixos-vm
```
