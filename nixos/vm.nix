{
  config,
  pkgs,
  ...
}: {
  # Placeholder bootloader/fs — overridden by qemu-vm wrapper from build-vm.
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  networking.hostName = "nixos-vm";

  users.users.david = {
    isNormalUser = true;
    initialPassword = "nixos";
    extraGroups = ["wheel"];
  };

  services.openssh.enable = true;

  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 4096;
      cores = 2;
      graphics = true;
      qemu.options = ["-vga virtio" "-display gtk,gl=off"];
      forwardPorts = [
        {
          from = "host";
          host.port = 2222;
          guest.port = 22;
        }
      ];
    };
  };

  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "david";
  };

  environment.systemPackages = with pkgs; [vim git];

  system.stateVersion = "25.11";
}
