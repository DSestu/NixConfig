## Launching the VM

Build the VM image:

```
nix build '.#nixosConfigurations.vm.config.system.build.vm'
```

Run the VM:

```
./result/bin/run-nixos-vm
```

### Graphical (QEMU window + GNOME/KDE)

```
nix build '.#nixosConfigurations.vm.config.system.build.vm' && ./result/bin/run-nixos-vm-vm
```

### Headless (serial console, output in your terminal)

```
nix build '.#nixosConfigurations.vm-headless.config.system.build.vm' && ./result/bin/run-nixos-vm-vm
```
