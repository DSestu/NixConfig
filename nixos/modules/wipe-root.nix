{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.profiles.impermanence;
  preserveCases = lib.concatStringsSep "|" cfg.preserveOnRoot;
in {
  # Initrd-time wipe of `/`. Runs after sysroot.mount and before the rootfs
  # is handed to PID 1, removing every top-level entry under /sysroot except
  # the names listed in `profiles.impermanence.preserveOnRoot`. Active mount
  # points are skipped defensively so the rm never crosses into a mounted
  # filesystem (the qemu profile depends on this — host 9p shares are
  # mounted under /mnt before this runs).
  #
  # Persistent state lives under /nix/persist and is bind-mounted back into
  # place by the impermanence module after pivot; see `nixos/base.nix` for
  # the `environment.persistence` map and `modules/persistence.nix` for the
  # home-manager equivalent.
  config = lib.mkIf cfg.enable {
    boot.initrd.systemd = {
      enable = lib.mkDefault true;
      storePaths = [pkgs.findutils pkgs.coreutils pkgs.util-linux pkgs.bash];
      services.wipe-root = {
        requiredBy = ["initrd-root-fs.target"];
        after = ["sysroot.mount"];
        before = ["initrd-root-fs.target"];
        unitConfig.DefaultDependencies = "no";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.bash}/bin/bash -euo pipefail -c 'for path in /sysroot/*; do [ -e \"$path\" ] || continue; base=\"$(basename \"$path\")\"; case \"$base\" in ${preserveCases}) continue ;; esac; if ${pkgs.util-linux}/bin/mountpoint -q \"$path\"; then continue; fi; ${pkgs.coreutils}/bin/rm -rf --one-file-system \"$path\"; done'";
        };
      };
    };
  };
}
