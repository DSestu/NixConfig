## Launching the VM

Build the VM image:

```
nix build '.#nixosConfigurations.vm.config.system.build.vm'
```

Run the VM:

```
./result/bin/run-nixos-vm
```
