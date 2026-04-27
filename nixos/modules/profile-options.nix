{lib, ...}: {
  options.profiles.impermanence = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable impermanence persistence wiring for this profile.";
    };

    preserveDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["nix" "boot" "tmp"];
      description = ''
        Top-level directories under `/` that survive the initrd
        `wipe-root` service on every boot. `nix` and `boot` are
        required (Nix store + bootloader); platform modules append
        their own (e.g. `vm-qemu` adds `mnt` for 9p shares and
        `var` for the QEMU runtime).
      '';
    };
  };
}
