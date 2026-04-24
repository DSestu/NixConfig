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

### Rebuild inside VM

```bash
nixos-rebuild switch
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
- Shared modules imported by both (with option guards)

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

- Home Manager: add `./modules/example.nix` to `imports` in `home.nix`.
- NixOS: add `./modules/example.nix` in `flake.nix` (`mkProfile`) or gate by profile flags.

### 3) Make module profile-aware (optional)

In `flake.nix` profile dictionary:

1. Add toggle in `profileDefaults.modules` (example: `example = false;`).
2. Override per profile (`profiles.<name>.modules.example = true/false;`).
3. Gate import with `lib.optionals cfg.modules.example [ ./modules/example.nix ]`.

### 4) Validate

```bash
home-manager switch --flake .#david
sudo nixos-rebuild switch --flake .#nixos-vm
```
