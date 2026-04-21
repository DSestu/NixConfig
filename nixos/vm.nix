{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../modules/kde.nix
  ];

  # Placeholder bootloader/fs — overridden by qemu-vm wrapper from build-vm.
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Impermanence: wipe-on-boot $HOME with an explicit whitelist (see modules/persistence.nix).
  fileSystems."/home/david" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = ["defaults" "size=2G" "mode=0755" "uid=1000" "gid=100"];
    neededForBoot = true;
  };

  systemd.tmpfiles.rules = [
    "d /nix/persist 0755 root root -"
  ];

  networking.hostName = "nixos-vm";

  services.xserver.xkb.layout = "fr";
  console.keyMap = "fr";

  users.users.david = {
    isNormalUser = true;
    initialPassword = "nixos";
    extraGroups = ["wheel"];
    shell = pkgs.fish;
  };

  services.openssh.enable = true;
  # System-wide fish shell
  programs.fish.enable = true;

  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 4096;
      cores = 2;
      # graphics is set per-output in flake.nix (vm vs vm-headless)
      qemu.options = ["-vga virtio" "-display gtk,gl=off"];
      forwardPorts = [
        {
          from = "host";
          host.port = 2222;
          guest.port = 22;
        }
      ];
      sharedDirectories.hmconfig = {
        source = "/home/david/.config/home-manager";
        target = "/mnt/hmconfig";
      };
    };
  };

  nix.settings.experimental-features = ["nix-command" "flakes"];

  services.displayManager.autoLogin = {
    enable = true;
    user = "david";
  };

  environment.systemPackages = [];

  system.stateVersion = "25.11";
}
