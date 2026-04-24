{
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

  systemd.tmpfiles.rules = [
    "d /nix/persist 0755 root root -"
    # Full flake lives on the host via VirtFS; link so `--flake /etc/nixos#...` works.
    "L+ /etc/nixos - - - - /mnt/hmconfig"
  ];

  # Wipe root on every boot, keeping only /nix (store + persist), /boot (GRUB),
  # and /mnt (CRITICAL: 9p shared directories from the host are mounted under
  # /mnt by the time this runs — `rm -rf` would cross the mount and destroy
  # files on the host filesystem).
  boot.initrd.systemd.storePaths = [pkgs.findutils pkgs.coreutils pkgs.util-linux pkgs.bash];
  boot.initrd.systemd.services.wipe-root = {
    requiredBy = ["initrd-root-fs.target"];
    after = ["sysroot.mount"];
    before = ["initrd-root-fs.target"];
    unitConfig.DefaultDependencies = "no";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -euo pipefail -c 'for path in /sysroot/*; do [ -e \"$path\" ] || continue; base=\"$(basename \"$path\")\"; case \"$base\" in nix|boot|mnt|tmp|var) continue ;; esac; if ${pkgs.util-linux}/bin/mountpoint -q \"$path\"; then continue; fi; ${pkgs.coreutils}/bin/rm -rf --one-file-system \"$path\"; done'";
    };
  };

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
