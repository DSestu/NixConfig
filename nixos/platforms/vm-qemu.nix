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
  # runtime state. `/run` must be preserved too: the qemu-vm wrapper schedules
  # a tmpfs at `/sysroot/run` in initrd, but its mount can race wipe-root —
  # if wipe-root sees the directory before the mount completes, `mountpoint
  # -q` returns false, the dir is removed, and the pending mount then fails
  # with "Failed to mount /sysroot/run" → emergency mode.
  profiles.impermanence.preserveDirs = ["nix" "boot" "mnt" "tmp" "var" "run"];

  systemd.tmpfiles.rules = [
    # Full flake lives on the host via VirtFS; link so `--flake /etc/nixos#...` works.
    "L+ /etc/nixos - - - - /mnt/hmconfig"
  ];

  # Flake-based systems omit `nixos-config` from NIX_PATH by default. Point it
  # at the shared checkout so plain `nixos-rebuild switch` resolves a file.
  #
  # `nixpkgs=flake:nixpkgs` is normally set by NixOS' `nixpkgs-flake.nix`
  # via `mkDefault`, but assigning `nix.nixPath` here at normal priority
  # would discard that default — leaving `nix-shell -p python3` and
  # `nix-build '<nixpkgs>' -A …` broken inside the VM. Repeat the entry
  # explicitly so both work. It resolves through the flake registry,
  # which `nixpkgs.flake.setFlakeRegistry` (also default-on) populates.
  nix.nixPath = [
    "nixpkgs=flake:nixpkgs"
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
