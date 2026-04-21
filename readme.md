## Export all plasma settings with

```bash
nix run github:nix-community/plasma-manager
```

## Update packages

```bash
nix flake update nixpkgs
```

## Launching the VM

Build the VM image:

```bash
nix build '.#nixosConfigurations.vm.config.system.build.vm'
```

Run the VM:

```bash
./result/bin/run-nixos-vm
```

### Graphical (QEMU window + GNOME/KDE)

Grab all keyboard shortcuts: `ctrl + alt + g`

```bash
nix build '.#nixosConfigurations.vm.config.system.build.vm' && ./result/bin/run-nixos-vm-vm -snapshot
```

### Headless (serial console, output in your terminal)

```bash
nix build '.#nixosConfigurations.vm-headless.config.system.build.vm' && ./result/bin/run-nixos-vm-vm -snapshot
```

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
