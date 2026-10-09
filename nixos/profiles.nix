# Profile dictionary — the source of truth for every machine this
# flake produces. Each entry is a small attrset describing the
# *intent* (hostname, hypervisor, impermanence yes/no, optional
# extras); `nixos/lib/mk-profile.nix` translates each entry into a
# `nixpkgs.lib.nixosSystem`.
#
# Each entry: { hostname, hypervisor, impermanence?, graphics?,
#               extraNixosImports?, extraHomeImports? }
#
# `root` is the flake's source path, threaded in so this file
# doesn't depend on its own location to resolve module paths.
{root}: let
  # ─── Shared desktop sugar (composed via `// {...}` below) ─────────
  # Adds the KDE Plasma stack on top of the baseline. Profiles can
  # still override or append.
  sharedDesktopProfile = {
    graphics = true;
    extraNixosImports = [(root + "/modules/nixos/kde-suite.nix")];
  };

  gamingHomeImport = root + "/modules/home/gaming.nix";
  wslHomeImport = root + "/modules/home/wsl-home.nix";
in {
  # ─────────────────────────────────────────────────────────────────
  # TEMPLATE — DO NOT EDIT, DO NOT DEPLOY.
  #
  # `_template-bare-metal` is the canonical starting point for any
  # new bare-metal profile. The leading underscore signals "skeleton
  # only" — never `nixos-rebuild` or `nixos-anywhere` against it
  # directly. Instead, copy this entry to a new key (e.g. `my-laptop`),
  # copy `nixos/hosts/_template-bare-metal/` to `nixos/hosts/my-laptop/`,
  # then customize the copy.
  # ─────────────────────────────────────────────────────────────────
  _template-bare-metal =
    sharedDesktopProfile
    // {
      # Placeholder hostname. The flake still evaluates with this
      # value, but you must rename when you copy this entry.
      hostname = "REPLACE-ME";
      hypervisor = "none";
      # Left off in the skeleton so a fresh copy installs predictably.
      # Flip to true once the copy imports the btrfs UEFI disko layout
      # (single-disk-uefi.nix) — that's what wipe-root.nix expects. The
      # flat ext4 BIOS layout has no @blank to roll back from.
      impermanence = false;
      extraHomeImports = [gamingHomeImport];
    };

  #### Bare-metal profiles ####
  nixos-desktop =
    sharedDesktopProfile
    // {
      hostname = "nixos-desktop";
      hypervisor = "none";
      extraHomeImports = [gamingHomeImport];
      impermanence = true;
    };

  # Installed into a VirtualBox VM via `nixos-anywhere` from a live
  # ISO. Bare-metal-style profile (hypervisor = "none"): the host
  # folder imports a disko layout and a hardware-configuration.nix,
  # exactly like `_template-bare-metal`. There is no "build an OVA
  # image" path — `nixos-anywhere` is the only supported flow.
  nixos-vbox =
    sharedDesktopProfile
    // {
      hostname = "nixos-vbox";
      hypervisor = "none";
      # Deliberately off: this guest's host folder ships its own
      # hardware-configuration.nix and GRUB-EFI override rather than
      # the btrfs subvolume layout wipe-root.nix needs.
      impermanence = false;
    };

  # Raspberry Pi 3/4/5, headless, aarch64. Boots from an SD image
  # built by nixpkgs' sd-image-aarch64 module (see the host folder).
  # No impermanence: no btrfs layout, so no wipe mechanism.
  nixos-rpi = {
    hostname = "nixos-rpi";
    hypervisor = "none";
    system = "aarch64-linux";
    graphics = false;
    impermanence = false;
    # home.nix pulls Chrome/Cursor/Steam etc. — x86-only and pointless
    # on a Pi. The host folder's home.nix replaces it.
    homeBaseline = false;
  };

  #### VMs ####
  nixos-vm =
    sharedDesktopProfile
    // {
      hostname = "nixos-vm";
      hypervisor = "qemu";
      impermanence = true;
      extraHomeImports = [
        gamingHomeImport
        (root + "/modules/home/network.nix")
      ];
    };

  nixos-vm-headless = {
    # No `sharedDesktopProfile` → no KDE, no graphics. Headless.
    hostname = "nixos-vm-headless";
    hypervisor = "qemu";
    graphics = false;
    impermanence = true;
    extraHomeImports = [
      (root + "/modules/home/network.nix")
    ];
  };

  # Test target for the bare-metal wipe-root + btrfs path. Same
  # composition as `nixos-desktop` (hypervisor = "none" → loads
  # wipe-root.nix + disko btrfs layout) but the host folder forces
  # /dev/vda and adds a boot-time canary that reports the wipe state
  # to the journal. See `scripts/run-vm-bare-test.sh` for the build
  # + boot harness.
  nixos-vm-bare-test = {
    hostname = "nixos-vm-bare-test";
    hypervisor = "none";
    impermanence = true;
    graphics = false;
  };

  #### WSL ####
  nixos-wsl = {
    hostname = "nixos-wsl";
    hypervisor = "wsl";
    # Keep disabled by default to avoid accidental ephemeral
    # behavior. Also guarantees no interaction with the Windows host
    # FS.
    impermanence = false;
    # WSL-specific HM tweaks. The host-folder home.nix (auto-
    # discovered by mkProfile) handles the per-profile fish
    # overrides.
    extraHomeImports = [wslHomeImport];
  };
}
