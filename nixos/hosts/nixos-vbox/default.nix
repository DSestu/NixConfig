{lib, ...}: {
  imports = [];

  # In VirtualBox with GPT + EFI system partition, install GRUB in EFI mode.
  # This avoids BIOS embedding errors ("GPT partition label ... bios boot").
  boot.loader.grub = {
    device = lib.mkForce "nodev";
    efiSupport = lib.mkForce true;
    efiInstallAsRemovable = lib.mkForce true;
  };

  fileSystems."/mnt/nixconfig" = {
    device = "NixConfig";
    fsType = "vboxsf";
    options = [
      "rw"
      "uid=1000"
      "gid=100"
      "dmode=0775"
      "fmode=0664"
    ];
  };
}
