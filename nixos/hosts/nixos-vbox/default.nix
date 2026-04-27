{lib, ...}: {
  imports = [];

  networking.hostName = lib.mkForce "nixos-vbox";

  # Use GRUB in EFI mode on this VM. `efiInstallAsRemovable` writes GRUB
  # to the EFI fallback path (`/EFI/BOOT/BOOTX64.EFI`), which makes it
  # the default boot entry without touching EFI variables (works well
  # with VirtualBox's limited NVRAM support).
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub = {
    enable = lib.mkForce true;
    device = lib.mkForce "nodev";
    efiSupport = lib.mkForce true;
    efiInstallAsRemovable = lib.mkForce true;
  };
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  fileSystems."/mnt/nixconfig" = {
    device = "NixConfig";
    fsType = "vboxsf";
    options = [
      "rw"
      "nofail"
      "x-systemd.automount"
      "uid=1000"
      "gid=100"
      "dmode=0775"
      "fmode=0664"
    ];
  };
}
