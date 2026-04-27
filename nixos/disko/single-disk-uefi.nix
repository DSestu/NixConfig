{lib, ...}: {
  # Single-disk UEFI layout for `nixos-anywhere` installs. Designed to be
  # compatible with the impermanence wipe-root pattern in
  # `../modules/impermanence-wipe.nix`:
  #
  #   - `/boot` is a separate FAT32 ESP. The wipe-root service preserves
  #     top-level `boot`, so the bootloader survives every wipe.
  #   - `/` is a single ext4 partition. `/nix/persist` lives as a regular
  #     directory under it; wipe-root preserves top-level `nix`, so
  #     persisted bind-mount sources survive.
  #   - No subvolumes, no swap, no LVM — keeps things simple and aligns
  #     with the OVA/QEMU layouts the rest of the flake uses.
  #
  # Override `disko.devices.disk.main.device` from the host folder if the
  # target's disk isn't `/dev/sda` (e.g. NVMe → `/dev/nvme0n1p`).
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
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  # Bootloader paired with the ESP above. `mkDefault` so a per-host module
  # can flip to GRUB or pin different EFI variables without an override
  # dance.
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
}
