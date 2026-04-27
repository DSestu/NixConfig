{
  modulesPath,
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [(modulesPath + "/virtualisation/virtualbox-image.nix")];

  virtualisation.virtualbox.guest.enable = true;

  # Mirror the impermanence pattern from vm-qemu.nix: a single ext4 root
  # (provided by virtualbox-image.nix) gets wiped on every boot. /nix
  # (store + /nix/persist) and /boot (bootloader) survive; everything
  # else is reconstructed from the Nix store on activation, with persisted
  # paths bind-mounted back into place by the impermanence module.
  systemd.tmpfiles.rules = lib.mkIf config.profiles.impermanence.enable [
    "d /nix/persist 0755 root root -"
  ];

  # systemd-in-initrd is required for the wipe-root service to run before
  # sysroot is handed off to PID 1.
  boot.initrd.systemd = lib.mkIf config.profiles.impermanence.enable {
    enable = true;
    storePaths = [pkgs.findutils pkgs.coreutils pkgs.util-linux pkgs.bash];
    services.wipe-root = {
      requiredBy = ["initrd-root-fs.target"];
      after = ["sysroot.mount"];
      before = ["initrd-root-fs.target"];
      unitConfig.DefaultDependencies = "no";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -euo pipefail -c 'for path in /sysroot/*; do [ -e \"$path\" ] || continue; base=\"$(basename \"$path\")\"; case \"$base\" in nix|boot|tmp) continue ;; esac; if ${pkgs.util-linux}/bin/mountpoint -q \"$path\"; then continue; fi; ${pkgs.coreutils}/bin/rm -rf --one-file-system \"$path\"; done'";
      };
    };
  };
}
