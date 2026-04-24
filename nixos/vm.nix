{
  config,
  pkgs,
  lib,
  ...
}: {
  nixpkgs.config.allowUnfree = true;

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

  systemd.tmpfiles.rules = [
    "d /nix/persist 0755 root root -"
    # Full flake lives on the host via VirtFS; link so `--flake /etc/nixos#vm` works.
    "L+ /etc/nixos - - - - /mnt/hmconfig"
  ];

  # Wipe root on every boot, keeping only /nix (store + persist), /boot (GRUB),
  # and /mnt (CRITICAL: 9p shared directories from the host are mounted under
  # /mnt by the time this runs — `rm -rf` would cross the mount and destroy
  # files on the host filesystem).
  boot.initrd.systemd.storePaths = [pkgs.findutils pkgs.coreutils];
  boot.initrd.systemd.services.wipe-root = {
    requiredBy = ["initrd-root-fs.target"];
    after = ["sysroot.mount"];
    before = ["initrd-root-fs.target"];
    unitConfig.DefaultDependencies = "no";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.findutils}/bin/find /sysroot -xdev -maxdepth 1 -mindepth 1 ! -name nix ! -name boot ! -name mnt -exec ${pkgs.coreutils}/bin/rm -rf {} +";
    };
  };

  # Required when using home.persistence (impermanence): keeps assigned
  # uids/gids stable across reboots instead of re-randomizing from /etc/passwd.
  environment.persistence."/nix/persist" = {
    directories = ["/var/lib/nixos"];
  };

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
      memorySize = 8192;
      cores = 8;
      # GTK UI is the reliable default on Linux (SDL often shows no window if QEMU lacks
      # SDL2 or the display stack disagrees). Host-side Gtk-Message lines about
      # colorreload/window-decorations are harmless; silence with:
      #   env GTK_MODULES= run-nixos-vm
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

  # Flake-based systems omit `nixos-config` from NIX_PATH by default (see
  # nixpkgs nixpkgs-flake.nix). Point it at the shared checkout so plain
  # `nixos-rebuild switch` resolves a file; that file only tells you to use --flake.
  nix.nixPath = [
    "nixos-config=/mnt/hmconfig/configuration.nix"
  ];

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
    persistent = true;
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "david";
  };

  environment.systemPackages = [];

  system.stateVersion = "25.11";
}
