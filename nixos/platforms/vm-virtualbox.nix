{modulesPath, ...}: {
  imports = [
    (modulesPath + "/virtualisation/virtualbox-image.nix")
    ../modules/impermanence-wipe.nix
  ];

  virtualisation.virtualbox.guest.enable = true;

  # Impermanence pattern: the single ext4 root provided by
  # `virtualbox-image.nix` is wiped on every boot by the shared `wipe-root`
  # initrd service in `../modules/impermanence-wipe.nix`. `/nix` (store +
  # /nix/persist) and `/boot` (bootloader) survive; everything else is
  # reconstructed from the Nix store on activation, with persisted paths
  # bind-mounted back from `/nix/persist` by the impermanence module
  # (config in `nixos/base.nix`).
  #
  # Default `profiles.impermanence.preserveDirs = ["nix" "boot" "tmp"]` is
  # what we want here — no extra mounts to preserve.
}
