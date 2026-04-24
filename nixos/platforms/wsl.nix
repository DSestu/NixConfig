{
  pkgs,
  ...
}: {
  wsl.enable = true;
  wsl.defaultUser = "david";

  # WSL does not boot with a Linux bootloader/initrd.
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub.enable = false;

  # Keep empty for now; add WSL utilities as needed.
  environment.systemPackages = with pkgs; [];
}
