{...}: {
  imports = [
    ../modules/impermanence-wipe.nix
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

  # `wipe-root` from `../modules/impermanence-wipe.nix` walks `/sysroot/*`
  # and `rm -rf`s anything not in `profiles.impermanence.preserveDirs`.
  # CRITICAL: 9p shared directories from the host are mounted under `/mnt`
  # by the time this runs — `rm -rf` would cross the mount and destroy
  # files on the host filesystem. `/var` is preserved for the qemu vmVariant
  # runtime state.
  profiles.impermanence.preserveDirs = ["nix" "boot" "mnt" "tmp" "var"];

  systemd.tmpfiles.rules = [
    # Full flake lives on the host via VirtFS; link so `--flake /etc/nixos#...` works.
    "L+ /etc/nixos - - - - /mnt/hmconfig"
  ];

  # Flake-based systems omit `nixos-config` from NIX_PATH by default. Point it
  # at the shared checkout so plain `nixos-rebuild switch` resolves a file.
  nix.nixPath = [
    "nixos-config=/mnt/hmconfig/configuration.nix"
  ];

  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 8192;
      cores = 8;
      # GTK UI is the reliable default on Linux.
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
}
