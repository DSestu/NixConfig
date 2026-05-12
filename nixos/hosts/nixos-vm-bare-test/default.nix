{
  config,
  lib,
  pkgs,
  ...
}: {
  # Test target for the bare-metal wipe-root + btrfs path. Boots from
  # a disko-built qcow2 in QEMU rather than the live VM variant — so
  # we can exercise the exact code path that runs on real hardware,
  # without needing real hardware.
  #
  # Build the image:
  #   nix run github:nix-community/disko -- \
  #     --mode disko-image --flake .#nixos-vm-bare-test
  #
  # Boot it with `./scripts/run-vm-bare-test.sh` — see that script for
  # the qemu invocation and the verification procedure.
  imports = [
    ../../disko/single-disk-uefi.nix
  ];

  # Virtio disk: the disko image is exposed as /dev/vda inside qemu.
  disko.devices.disk.main.device = lib.mkForce "/dev/vda";

  # Kernel modules needed to find the virtio root disk in initrd.
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
    "virtio_balloon"
    "virtio_rng"
    "virtio_console"
    "ahci"
    "sd_mod"
  ];

  # The wipe-root service unconditionally mounts /dev/disk/by-label/nixos.
  # Disko's image builder needs the same kernel modules to format the
  # filesystem in the first place.
  boot.kernelModules = ["kvm-intel" "kvm-amd"];

  # No graphics inside the test VM — keeps the boot fast and matches
  # what we actually want to test (the wipe behavior, not the desktop).
  services.xserver.enable = lib.mkForce false;
  services.displayManager.sddm.enable = lib.mkForce false;
  services.displayManager.autoLogin.enable = lib.mkForce false;

  # Auto-login on tty1 so we can poke at the VM without typing
  # passwords. Test-only; never enable on a real bare-metal profile.
  services.getty.autologinUser = "david";

  # Make the verification trivial: every boot, dump the canary state
  # so we can read it off the journal / serial console.
  systemd.services.wipe-canary-report = {
    description = "Report wipe-root canary state at boot";
    wantedBy = ["multi-user.target"];
    after = ["local-fs.target"];
    serviceConfig.Type = "oneshot";
    script = ''
      echo "=== wipe-root canary report ==="
      echo "boot id: $(cat /proc/sys/kernel/random/boot_id)"
      echo "uptime:  $(cat /proc/uptime | cut -d' ' -f1)s"
      if [ -e /root-canary ]; then
        echo "FAIL: /root-canary exists → @ was NOT wiped"
      else
        echo "OK:   /root-canary absent  → @ was wiped (or first boot)"
      fi
      if [ -e /nix/persist/persist-canary ]; then
        echo "OK:   /nix/persist/persist-canary preserved across boot"
      else
        echo "info: /nix/persist/persist-canary absent (first boot or test not yet seeded)"
      fi
      echo "==============================="
    '';
  };
}
