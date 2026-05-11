{lib, ...}: {
  options.profiles.impermanence = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable impermanence persistence wiring for this profile. The
        actual mechanism is tmpfs root + a persistent `/nix/persist`
        directory on disk, set up per-platform (see
        `nixos/platforms/vm-qemu.nix`, `nixos/platforms/vm-virtualbox.nix`,
        and the disko layouts in `nixos/disko/`). When enabled, this
        flag also gates `environment.persistence` in `nixos/base.nix`
        and auto-imports `modules/home/persistence.nix` on the
        Home Manager side (see `mkProfile` in `flake.nix`).
      '';
    };
  };
}
