{...}: {
  wsl.enable = true;
  wsl.defaultUser = "david";

  # No `metadata` (the NixOS-WSL default): Windows-side saves drop the Linux
  # mode bits, so every repo on /mnt/* showed 644 -> 755 noise. Without it
  # git's chmod probe fails and init/clone write core.fileMode=false there.
  wsl.wslConf.automount.options = "uid=1000,gid=100";

  # WSL does not boot with a Linux bootloader/initrd.
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub.enable = false;

  # Trusted users may override restricted Nix settings (e.g. `--option sandbox
  # false`, custom substituters). Required when debugging build sandbox issues
  # like `cptofs` EINVAL during OVA builds. Root is always trusted; we add
  # `david` so per-build flags work without re-rebuilding.
  nix.settings.trusted-users = ["root" "david"];
}
