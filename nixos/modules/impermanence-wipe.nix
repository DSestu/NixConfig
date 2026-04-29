{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.profiles.impermanence;
  preserveCases = lib.concatStringsSep "|" cfg.preserveDirs;

  # Robust wipe script. Two non-obvious things it has to handle:
  #
  #   1. NixOS marks a few paths immutable via `chattr +i` (notably
  #      `/var/empty`, used as sshd's privsep chroot). Plain `rm -rf`
  #      bails on those with EPERM. We strip the immutable bit first.
  #
  #   2. We do NOT use `set -e`. A single rm failure must not abort the
  #      whole wipe — the next boot's persistence map depends on as many
  #      top-level dirs as possible being clean. We let `rm` report what
  #      it can, swallow the exit code, and move on. The service itself
  #      always exits 0 so a stubborn file doesn't drop the box into
  #      emergency mode.
  wipeScript = pkgs.writeShellScript "wipe-root" ''
    set -uo pipefail
    for path in /sysroot/*; do
      [ -e "$path" ] || continue
      base="$(basename "$path")"
      case "$base" in
        ${preserveCases})
          continue
          ;;
      esac
      if ${pkgs.util-linux}/bin/mountpoint -q "$path"; then
        continue
      fi
      # Strip immutable / append-only attrs anywhere under this path.
      ${pkgs.e2fsprogs}/bin/chattr -R -i -a "$path" 2>/dev/null || true
      ${pkgs.coreutils}/bin/rm -rf --one-file-system "$path" || true
    done

    # Make sure /nix/persist exists before stage-2 boots. Why here and not
    # via `systemd.tmpfiles.rules`? Tmpfiles-setup runs *after* the
    # impermanence bind-mount units (both ride local-fs.target), so on
    # first boot the persist mounts try to bind a path whose parent dir
    # doesn't exist yet and fail with "no such file or directory" — the
    # `failed bound persist etc shadow` symptom. Creating the dir here, in
    # initrd, while we have /sysroot mounted, sidesteps the ordering loop.
    ${pkgs.coreutils}/bin/mkdir -p /sysroot/nix/persist

    exit 0
  '';
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
      # Allow entering rescue.target without a password if a unit fails in
      # initrd. Without this, a failed `wipe-root` (or anything else
      # `requiredBy = initrd-root-fs.target`) lands you at "press any key
      # to terminate" with no way to inspect the journal — see issue trail
      # in CONTRIBUTING / README. Fine for development VMs; for hardened
      # bare-metal you'd want this off (or guarded behind a profile flag).
      emergencyAccess = true;
      # `chattr` lives in e2fsprogs and is required by the wipe script
      # to strip the immutable bit off paths like `/var/empty`. Without
      # it the wipe fails on the very first NixOS-managed immutable file.
      #
      # `wipeScript` itself must also be in `storePaths` — otherwise its
      # `/nix/store/...-wipe-root` path isn't copied into the initramfs
      # and systemd fails with "unable to locate executable" before the
      # script even runs.
      storePaths = [pkgs.coreutils pkgs.util-linux pkgs.bash pkgs.e2fsprogs wipeScript];
      services.wipe-root = {
        requiredBy = ["initrd-root-fs.target"];
        after = ["sysroot.mount"];
        before = ["initrd-root-fs.target"];
        unitConfig.DefaultDependencies = "no";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${wipeScript}";
        };
      };
    };
  };
}
