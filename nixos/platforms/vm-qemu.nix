{...}: {
  # Placeholder bootloader/fs — overridden by qemu-vm wrapper from build-vm.
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };

  # Impermanence via tmpfs root: `/` is a fresh tmpfs every boot, no wipe
  # service required. The qcow2 disk holds `/nix` (Nix store + persisted
  # state under `/nix/persist`); impermanence bind-mounts paths from
  # `/nix/persist` back into the tmpfs root.
  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = ["defaults" "size=2G" "mode=755"];
  };
  fileSystems."/nix" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    neededForBoot = true;
  };

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
      # Stop the qemu vmVariant from injecting its own
      # `fileSystems."/" = ext4 disk` via `mkVMOverride` (priority 10),
      # which beats both `mkForce` (50) and even `mkOverride 9`. With
      # this off, the `fileSystems` declared above (tmpfs `/`, ext4
      # `/nix`) are the source of truth and the qcow2 disk is mounted
      # at `/nix` instead of `/`.
      useDefaultFilesystems = false;
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
