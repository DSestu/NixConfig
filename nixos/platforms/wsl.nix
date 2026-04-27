{
  pkgs,
  ...
}: {
  wsl.enable = true;
  wsl.defaultUser = "david";

  # WSL does not boot with a Linux bootloader/initrd.
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub.enable = false;

  # Trusted users may override restricted Nix settings (e.g. `--option sandbox
  # false`, custom substituters). Required when debugging build sandbox issues
  # like `cptofs` EINVAL during OVA builds. Root is always trusted; we add
  # `david` so per-build flags work without re-rebuilding.
  nix.settings.trusted-users = ["root" "david"];

  # Keep empty for now; add WSL utilities as needed.
  environment.systemPackages = with pkgs; [];
}
