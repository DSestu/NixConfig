{
  config,
  lib,
  pkgs,
  ...
}: {
  # "nodev" prevents GRUB from trying to write its boot record to the
  # block device from inside a running VM (which fails with blkid errors).
  # The actual boot is handled by the host's run script, not by GRUB.
  boot.loader.grub = {
    enable = true;
    device = "nodev";
  };

  # Bootstrap boot-critical paths in the tmpfs root.
  #
  # Only needed when impermanence is enabled (tmpfs `/`). On a normal
  # disk-backed root these paths survive from the first install.
  #
  # With stage1 systemd + tmpfs `/`, `initrd-nixos-activation` chroots into
  # `/sysroot` and runs the activation script, then `initrd-switch-root`
  # runs `systemctl switch-root /sysroot ""`. Two checks then fire in the
  # new root that an empty tmpfs fails:
  #
  #   1. `switch-root` with empty next-init falls back to `/sbin/init` —
  #      a fresh tmpfs has none. Fails with "no usable init".
  #   2. systemd 258+ refuses to start when `/usr/` is empty (merged-usr
  #      detection). Even with NixOS' `usrbinenv` activation creating
  #      `/usr/bin/env`, the order can leave `/usr` empty at the moment
  #      systemd inspects it. Fails with "Refusing to run in unsupported
  #      environment where /usr/ is not populated".
  #
  # Seed them here so a freshly-tmpfs'd root passes both checks.
  system.activationScripts.bootstrapTmpfsRoot = lib.mkIf config.profiles.impermanence.enable {
    text = ''
      install -m 0755 -d /sbin /usr/bin /usr/lib
      ln -sfn ${config.systemd.package}/lib/systemd/systemd /sbin/init
      ln -sfn ${pkgs.coreutils}/bin/env /usr/bin/env
      ln -sfn /etc/os-release /usr/lib/os-release
    '';
  };

  # Restore /run/{current,booted}-system early in stage2. Only needed
  # with tmpfs root (impermanence): the initrd activation creates these
  # in /sysroot/run, but switch-root may not preserve them across the
  # pivot — without them, user shells fail with ENOENT at login.
  #
  # We read the closure path from the kernel command line (`init=…/init`)
  # rather than `config.system.build.toplevel` — referencing toplevel
  # from a service that's part of toplevel triggers infinite recursion.
  systemd.services.bootstrap-current-system = lib.mkIf config.profiles.impermanence.enable {
    description = "Re-create /run/{current,booted}-system after switch-root";
    wantedBy = ["sysinit.target"];
    before = ["sysinit.target" "local-fs.target"];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "bootstrap-current-system" ''
        set -euo pipefail
        for arg in $(< /proc/cmdline); do
          case "$arg" in
            init=*)
              closure="$(${pkgs.coreutils}/bin/dirname "''${arg#init=}")"
              ${pkgs.coreutils}/bin/ln -sfn "$closure" /run/current-system
              ${pkgs.coreutils}/bin/ln -sfn "$closure" /run/booted-system
              exit 0
              ;;
          esac
        done
      '';
    };
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

  # Top-level fileSystems mirror the vmVariant entries so `nixos-rebuild switch`
  # run from inside a running VM sees a valid root and doesn't trip the
  # "fileSystems does not specify your root file system" assertion.
  fileSystems = lib.mkIf config.profiles.impermanence.enable {
    "/" = {
      device = "none";
      fsType = "tmpfs";
      options = ["defaults" "size=2G" "mode=755"];
    };
    "/nix" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
      neededForBoot = true;
    };
  };

  virtualisation.vmVariant = {
    virtualisation = {
      # When impermanence is enabled, disable the qemu-vm default ext4
      # root injection (`mkVMOverride`, priority 10, beats mkForce) and
      # supply our own tmpfs `/` + ext4 `/nix` on the labelled qcow2.
      # When impermanence is off, leave useDefaultFilesystems at its
      # default (true) so qemu-vm creates a normal ext4 root disk.
      useDefaultFilesystems = lib.mkIf config.profiles.impermanence.enable false;
      fileSystems = lib.mkIf config.profiles.impermanence.enable {
        "/" = {
          device = "none";
          fsType = "tmpfs";
          options = ["defaults" "size=2G" "mode=755"];
        };
        "/nix" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
          neededForBoot = true;
        };
      };
      memorySize = 8192;
      cores = 8;
      # gl=off — software rendering. gl=on (virglrenderer pass-through)
      # crashes on this host with "GtkGLArea console lacks DMABUF support"
      # because the system's GTK build lacks DMABUF/EGL context support.
      # Revisit once the host qemu/GTK gains it.
      qemu.options = ["-vga" "virtio" "-display" "gtk,gl=off"];
      # Raise 9p msize from the 16384-byte default. The nix store share
      # (/nix/.ro-store) transfers many small files; a larger packet size
      # cuts round-trips and measurably reduces store-read latency in the VM.
      msize = 131072;
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
