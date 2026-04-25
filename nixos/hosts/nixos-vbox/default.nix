{...}: {
  imports = [
    # ./hardware-configuration.nix
  ];

  fileSystems."/mnt/nixconfig" = {
    device = "nixconfig";
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
