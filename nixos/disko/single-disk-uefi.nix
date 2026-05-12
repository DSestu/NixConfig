{lib, ...}: {
  # Single-disk UEFI layout with btrfs subvolumes, designed for the
  # `wipe-root` impermanence pattern in `../modules/wipe-root.nix`:
  #
  #   - `/boot` is a separate FAT32 ESP. It's outside the btrfs
  #     filesystem entirely, so the bootloader is unaffected by the
  #     subvolume rollback.
  #   - The remaining space is one btrfs filesystem labelled `nixos`
  #     (the wipe-root service looks for it via
  #     `/dev/disk/by-label/nixos`) with four subvolumes:
  #
  #       @         → /             (WIPED on every boot — rolled back
  #                                  from @blank by the initrd service)
  #       @blank    → unmounted     (immutable empty subvolume used as
  #                                  the rollback source — kept read-
  #                                  only by an activation script so
  #                                  nothing can accidentally write to
  #                                  it)
  #       @nix      → /nix          (store + bootloader payload — must
  #                                  survive the wipe or the system
  #                                  won't reboot)
  #       @persist  → /nix/persist  (impermanence's persisted-files
  #                                  source — `environment.persistence`
  #                                  and `home.persistence` bind-mount
  #                                  paths from here back into `/` and
  #                                  `/home` on each boot)
  #       @log      → /var/log      (journal + service logs survive
  #                                  reboots without polluting @persist)
  #
  # Override `disko.devices.disk.main.device` from the host folder if
  # the target's disk isn't `/dev/sda` (e.g. NVMe → `/dev/nvme0n1`).
  #
  # Used by importing it from a per-host module, e.g.:
  #
  #   # nixos/hosts/<profile-name>/default.nix
  #   { ... }: {
  #     imports = [ ../../disko/single-disk-uefi.nix ];
  #   }
  disko.devices.disk.main = {
    type = "disk";
    device = lib.mkDefault "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = ["umask=0077"];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = ["-L" "nixos" "-f"];
            subvolumes = {
              "@" = {
                mountpoint = "/";
                mountOptions = ["compress=zstd" "noatime"];
              };
              "@blank" = {
                # Never mounted. Stays empty so the initrd rollback
                # restores a pristine `/` from it on every boot.
              };
              "@nix" = {
                mountpoint = "/nix";
                mountOptions = ["compress=zstd" "noatime"];
              };
              "@persist" = {
                mountpoint = "/nix/persist";
                mountOptions = ["compress=zstd" "noatime"];
              };
              "@log" = {
                mountpoint = "/var/log";
                mountOptions = ["compress=zstd" "noatime"];
              };
            };
          };
        };
      };
    };
  };

  # `/nix/persist` must be mounted in stage-1 because impermanence
  # uses it as the bind-mount source for paths declared in
  # `environment.persistence`. Without `neededForBoot`, those bind
  # mounts fire before the filesystem is available and activation
  # fails with "directory does not exist".
  fileSystems."/nix/persist".neededForBoot = true;

  # Mark @blank read-only after first activation so nothing can leak
  # state into the rollback source. Setting RO on an already-RO
  # subvolume is a no-op, so this is safe to re-run on every rebuild.
  system.activationScripts.lockBlankSubvol = {
    text = ''
      if [ -d /nix/persist ] && command -v btrfs >/dev/null 2>&1; then
        # Mount the raw filesystem to reach @blank (which is unmounted
        # in the normal subvolume layout).
        tmp=$(mktemp -d)
        if mount -t btrfs -o subvol=/ /dev/disk/by-label/nixos "$tmp" 2>/dev/null; then
          if [ -d "$tmp/@blank" ]; then
            btrfs property set -ts "$tmp/@blank" ro true 2>/dev/null || true
          fi
          umount "$tmp"
        fi
        rmdir "$tmp"
      fi
    '';
    deps = [];
  };

  # Bootloader paired with the ESP above. `mkDefault` so a per-host
  # module can flip to GRUB or pin different EFI variables without an
  # override dance.
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
}
