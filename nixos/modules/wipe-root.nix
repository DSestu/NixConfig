{
  config,
  lib,
  ...
}: {
  # Btrfs subvolume rollback in stage-1 initrd.
  #
  # On every boot, the `@` subvolume (mounted at `/`) is destroyed and
  # re-created from `@blank` — an empty subvolume snapshotted at install
  # time and never written to since. Anything that needs to survive
  # reboots lives on a different subvolume (`@nix`, `@persist`, `@log`)
  # and is unaffected by the rollback.
  #
  # The previous `@` is moved to `@old_roots/<timestamp>` rather than
  # deleted outright — this gives a 30-day grace window to recover
  # accidentally-clobbered state with `btrfs subvolume snapshot
  # @old_roots/<ts> @` from a rescue boot. Old roots beyond 30 days are
  # garbage-collected by the same service.
  #
  # Paired with `nixos/disko/single-disk-uefi.nix`, which provisions the
  # btrfs filesystem with label `nixos` and the four subvolumes the
  # rollback expects. Loaded automatically by `mkProfile` when both
  # `profiles.impermanence.enable` and a bare-metal hypervisor
  # (`hypervisor = "none"`) are set.

  config = lib.mkIf config.profiles.impermanence.enable {
    boot.initrd.supportedFilesystems = ["btrfs"];

    boot.initrd.systemd.services.rollback-root = {
      description = "Rollback btrfs `@` subvolume to blank snapshot";
      wantedBy = ["initrd.target"];
      after = ["dev-disk-by\\x2dlabel-nixos.device"];
      before = ["sysroot.mount"];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p /btrfs_tmp
        mount -t btrfs -o subvol=/ /dev/disk/by-label/nixos /btrfs_tmp

        if [[ -e /btrfs_tmp/@ ]]; then
          mkdir -p /btrfs_tmp/@old_roots
          timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/@)" "+%Y-%m-%-d_%H:%M:%S")
          mv /btrfs_tmp/@ "/btrfs_tmp/@old_roots/$timestamp"
        fi

        delete_subvolume_recursively() {
          IFS=$'\n'
          for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
            delete_subvolume_recursively "/btrfs_tmp/$i"
          done
          btrfs subvolume delete "$1"
        }

        if [[ -d /btrfs_tmp/@old_roots ]]; then
          for i in $(find /btrfs_tmp/@old_roots/ -maxdepth 1 -mtime +30 -mindepth 1); do
            delete_subvolume_recursively "$i"
          done
        fi

        btrfs subvolume snapshot /btrfs_tmp/@blank /btrfs_tmp/@
        umount /btrfs_tmp
      '';
    };
  };
}
