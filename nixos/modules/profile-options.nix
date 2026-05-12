{lib, ...}: {
  options.profiles.impermanence = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable impermanence persistence wiring for this profile. The
        mechanism varies by platform:

          - VM profiles (`hypervisor = "qemu"`) use a tmpfs `/`
            seeded by `nixos/platforms/vm-qemu.nix` plus an ext4
            `/nix` on the qcow2.
          - Bare-metal (`hypervisor = "none"`) uses a btrfs subvolume
            rollback initrd service from
            `nixos/modules/wipe-root.nix`, paired with the disko
            layout in `nixos/disko/single-disk-uefi.nix`.

        In both cases enabling this flag gates `environment.persistence`
        in `nixos/base.nix` and auto-imports
        `modules/home/persistence.nix` on the Home Manager side (see
        `mkProfile` in `flake.nix`).
      '';
    };
  };
}
