{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.profiles.impermanence;
  preserveCases = lib.concatStringsSep "|" cfg.preserveDirs;
in {
  # Shared impermanence implementation: an initrd `wipe-root` service that
  # runs after `sysroot.mount` (so `/` is visible as `/sysroot`) and before
  # `initrd-root-fs.target` (so the wipe finishes before PID 1 starts), then
  # `rm -rf`s every top-level entry that isn't in `profiles.impermanence.preserveDirs`.
  #
  # The actual list of paths bind-mounted back from `/nix/persist` is in
  # `nixos/base.nix` (`environment.persistence."/nix/persist"`) and
  # `modules/persistence.nix` (`home.persistence."/nix/persist"`).
  #
  # Used by:
  #   - `nixos/platforms/vm-qemu.nix`        (QEMU vmVariant)
  #   - `nixos/platforms/vm-virtualbox.nix`  (OVA build)
  #   - any disko-based bare-metal profile (see `nixos/disko/`)
  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /nix/persist 0755 root root -"
    ];

    boot.initrd.systemd = {
      enable = true;
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
