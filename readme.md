## Export all plasma settings with

```bash
nix run github:nix-community/plasma-manager
```

## Update packages

```bash
nix flake update nixpkgs
```

## Garbage collect

```bash
nix-collect-garbage -d
```

## Launching the VM

### Graphical (QEMU window + KDE)

Grab all keyboard shortcuts: `ctrl + alt + g`

```bash
nix build '.#nixosConfigurations.nixos-vm.config.system.build.vm' && ./result/bin/run-nixos-vm -snapshot
```

### Headless (serial console, output in your terminal)

```bash
nix build '.#nixosConfigurations.nixos-vm-headless.config.system.build.vm' && ./result/bin/run-nixos-vm-headless-vm -snapshot
```

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
