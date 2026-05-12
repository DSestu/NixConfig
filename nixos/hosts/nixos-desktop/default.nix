{lib, ...}: {
  # Bare-metal host entry point for the `nixos-desktop` profile.
  # Drop additional host-specific modules (bootloader tweaks, hardware
  # quirks, filesystems, etc.) here.
  #
  # `hardware-configuration.nix` must be generated on the target machine
  # via `sudo nixos-generate-config --show-hardware-config > .../hardware-configuration.nix`
  # and committed next to this file. The import is guarded so the rest of
  # the flake still evaluates before that file has been produced.
  imports = lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;
}
