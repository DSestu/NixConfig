{lib, ...}: {
  # Single-disk BIOS/MBR-on-GPT layout for `nixos-anywhere` installs onto
  # legacy-firmware targets — VirtualBox VMs created without "Enable EFI"
  # (the default), older bare metal without UEFI, etc.
  #
  #   - 1 MiB BIOS-boot partition for GRUB stage 2 (no FS, just a marker).
  #   - `/` is a single ext4 partition; `/boot` lives on it (GRUB doesn't
  #     need a separate boot partition on BIOS).
  #
  # NOT usable with `impermanence = true`: this is a flat ext4 layout
  # with no btrfs subvolumes, so `wipe-root.nix` has no `@blank` to roll
  # `@` back from. Use `single-disk-uefi.nix` for impermanent hosts.
  #
  # Override `disko.devices.disk.main.device` from the host folder if the
  # target's disk isn't `/dev/sda`.
  #
  # Used by importing it from a per-host module, e.g.:
  #
  #   # nixos/hosts/<profile-name>/default.nix
  #   { ... }: {
  #     imports = [ ../../disko/single-disk-bios.nix ];
  #   }
  disko.devices.disk.main = {
    type = "disk";
    device = lib.mkDefault "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        # GRUB stage 2 lives here. No filesystem, no mountpoint.
        boot = {
          size = "1M";
          type = "EF02";
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

  boot.loader.grub = {
    enable = lib.mkDefault true;
    device = lib.mkDefault "/dev/sda";
    efiSupport = lib.mkDefault false;
  };
  boot.loader.systemd-boot.enable = lib.mkDefault false;
}
