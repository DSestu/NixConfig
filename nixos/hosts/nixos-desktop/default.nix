{lib, ...}: {
  # Bare-metal host entry point for the `nixos-desktop` profile.
  # Drop additional host-specific modules (bootloader tweaks, hardware
  # quirks, filesystems, etc.) here.
  #
  # The disko UEFI layout (btrfs subvols paired with `wipe-root.nix`)
  # is imported unconditionally. `hardware-configuration.nix` must be
  # generated on the target machine via `nixos-anywhere
  # --generate-hardware-config`; it's imported with a `pathExists`
  # guard so the flake still evaluates before that file is produced.
  imports =
    [../../disko/single-disk-uefi.nix]
    ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;
}
