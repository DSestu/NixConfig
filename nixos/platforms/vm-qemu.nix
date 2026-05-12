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

  # Bootstrap boot-critical paths in the tmpfs root.
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
  # On disk-backed NixOS roots these paths survive from the first install,
  # so nothing in upstream creates them eagerly. Seed them here so a
  # freshly-tmpfs'd root passes both checks.
  system.activationScripts.bootstrapTmpfsRoot.text = ''
    install -m 0755 -d /sbin /usr/bin /usr/lib
    ln -sfn ${config.systemd.package}/lib/systemd/systemd /sbin/init
    ln -sfn ${pkgs.coreutils}/bin/env /usr/bin/env
    ln -sfn /etc/os-release /usr/lib/os-release
  '';

  # Restore /run/{current,booted}-system early in stage2. The initrd
  # activation creates these in the bind-mounted /sysroot/run, but
  # systemd's switch-root may not preserve them across the pivot — and
  # without them, user shells (set to `/run/current-system/sw/bin/fish`
  # by `utils.toShellPath`) fail with ENOENT at login.
  #
  # We read the closure path from the kernel command line (`init=…/init`)
  # rather than `config.system.build.toplevel` — referencing toplevel
  # from a service that's part of toplevel triggers infinite recursion.
  systemd.services.bootstrap-current-system = {
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

  virtualisation.vmVariant = {
    virtualisation = {
      # Stop the qemu vmVariant from injecting its own
      # `fileSystems."/" = ext4 disk` via `mkVMOverride` (priority 10),
      # which beats both `mkForce` (50) and even `mkOverride 9`. With
      # this off, the `fileSystems` declared above (tmpfs `/`, ext4
      # `/nix`) are the source of truth and the qcow2 disk is mounted
      # at `/nix` instead of `/`.
      useDefaultFilesystems = false;
      # qemu-vm.nix reads `virtualisation.fileSystems` and `mkVMOverride`s
      # them into the VM's actual `fileSystems`. Declaring top-level
      # `fileSystems` here does NOT propagate into the vmVariant when
      # `useDefaultFilesystems = false`, so put the root + /nix here.
      fileSystems = {
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
