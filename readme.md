## Export all plasma settings with

```bash
nix run github:nix-community/plasma-manager
```

## Update packages

```bash
nix flake update nixpkgs
```

## Update a remote machine from local

Run from this repo on your local machine:

```bash
sudo nixos-rebuild switch --flake .#<profile-name> --target-host <user>@<remote-host> --use-remote-sudo
```

Example:

```bash
sudo nixos-rebuild switch --flake .#nixos-vm --target-host david@192.168.1.50 --use-remote-sudo
```

Optional dry-run style build first:

```bash
sudo nixos-rebuild build --flake .#<profile-name> --target-host <user>@<remote-host> --use-remote-sudo
```

## Remote install/push over SSH with nixos-anywhere

`nixos-anywhere` is best for first install or full reprovision over SSH.

WARNING: this is destructive by default (it can repartition/reinstall the target machine).

From this repo on your local machine:

```bash
nixos-anywhere --flake .#<profile-name> <user>@<remote-host>
```

Example:

```bash
nixos-anywhere --flake .#nixos-vm root@192.168.1.50
```

If `nixos-anywhere` is not on PATH yet, run via nix:

```bash
nix run github:nix-community/nixos-anywhere -- --flake .#<profile-name> <user>@<remote-host>
```

## Garbage collect

```bash
nix-collect-garbage -d
```

## Launching the VM

VM targets now reuse the same base machine config as real-machine targets. Only hypervisor-specific bits differ.

### Graphical (QEMU window + KDE)

Grab all keyboard shortcuts: `ctrl + alt + g`

```bash
./scripts/run-vm-gui.sh
```

### Headless (serial console, output in your terminal)

```bash
./scripts/run-vm-headless.sh
```

### VirtualBox (build OVA image)

```bash
./scripts/build-vbox-ova.sh
```

Import the generated `*.ova` from `./result/` into VirtualBox, then start it from the VirtualBox UI.

### Rebuilding inside the VM

```bash
nixos-rebuild switch
```

The flake attribute is auto-detected from the hostname, so no `--flake` flag is needed.

## Virtualisation performance issues

### KVM Acceleration

To ensure optimal VM performance, verify that KVM acceleration is enabled. Without KVM, the VM will run 10-20× slower regardless of the number of cores assigned.

Check if you are in the `kvm` group:

```bash
groups | grep -q kvm && echo "KVM enabled" || echo "You need to join the kvm group"
```

If you are not a member, add yourself to the `kvm` group and re-login:

```bash
sudo usermod -aG kvm david
```

Then log out and log back in for the changes to take effect.

## Adding a new module

This repo supports three common module patterns:

- Home Manager only module (user-level config/packages)
- NixOS only module (system services/kernel/networking)
- Shared module imported by both, with option guards

### 1) Create the module file

Example:

```bash
mkdir -p modules
micro modules/example.nix
```

Minimal Home Manager module template:

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

### 2) Wire it where it belongs

Home Manager (always loaded for user `david`):

- Add `./modules/example.nix` to `imports` in `home.nix`.

NixOS (loaded per profile/host):

- Add `./modules/example.nix` to the `modules` list in `flake.nix` inside `mkProfile` (global), or gate it with a profile flag (recommended).

### 3) If you want per-profile enable/disable

Use the profile dictionary in `flake.nix`:

1. Add a new toggle in `profileDefaults.modules`, for example `example = false;`
2. Set it per profile under `profiles.<name>.modules.example = true/false;`
3. Gate import/config with `lib.optionals cfg.modules.example [ ./modules/example.nix ]`

This keeps module selection declarative and centralized.

### 4) Build/test

Home Manager check:

```bash
home-manager switch --flake .#david
```

NixOS profile check:

```bash
sudo nixos-rebuild switch --flake .#nixos-vm
```

Or for headless:

```bash
sudo nixos-rebuild switch --flake .#nixos-vm-headless
```
