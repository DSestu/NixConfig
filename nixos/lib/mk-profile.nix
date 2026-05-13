# Profile assembler. Takes a profile entry (the small attrset
# declared in `nixos/profiles.nix` or inline in `flake.nix`) and
# produces a `nixpkgs.lib.nixosSystem` with the five composition
# ingredients wired in:
#
#   1. commonNixosModules    — system-wide baseline (every profile)
#   2. commonHomeImports     — user-wide baseline   (every profile)
#   3. host folder           — auto-discovered from
#                              `nixos/hosts/<name>/{default.nix,home.nix}`
#   4. impermanence flag     — flips profiles.impermanence.enable on,
#                              auto-adds modules/home/persistence.nix,
#                              and on bare-metal loads wipe-root.nix
#   5. extras + platform     — extraNixosImports / extraHomeImports
#                              from the profile entry, plus the module
#                              for `hypervisor = "..."`
#
# Anything that needs to reach flake-relative paths (host folders,
# the impermanence persistence module, the platform modules, the
# wipe-root module) receives `root` as the flake source — anchoring
# avoids depending on this file's own location.
{
  lib,
  system,
  root,
  commonNixosModules,
  commonHomeImports,
  nixos-wsl,
  plasma-manager,
}: name: profile: let
  # Defaults for optional per-profile fields.
  cfg =
    {
      graphics = true;
      extraNixosImports = [];
      extraHomeImports = [];
      impermanence = false;
    }
    // profile;

  # ── 3. Host folder (auto-discovered) ──────────────────────────
  # `nixos/hosts/<name>/default.nix` → NixOS-side host module
  # `nixos/hosts/<name>/home.nix`    → HM-side    host module
  # Both optional. Drop in either to add per-profile config without
  # touching the profile table. Each can `imports = [./nixos/...]`
  # or `imports = [./home/...]` to organize per-host sub-modules.
  hostDir = root + "/nixos/hosts/${name}";
  hostNixosImports =
    lib.optional (builtins.pathExists (hostDir + "/default.nix")) hostDir;
  hostHomeImports =
    lib.optional (builtins.pathExists (hostDir + "/home.nix"))
    (hostDir + "/home.nix");

  # ── Profile wiring (translates the profile entry into config) ──
  profileWiring = {
    networking.hostName = cfg.hostname;
    profiles.impermanence.enable = cfg.impermanence;
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "bak";
      users.david.imports =
        # 2. Common HM baseline.
        commonHomeImports
        # 4. Impermanence: auto-add the user-side persistence map.
        # The HM module is auto-imported by the NixOS module
        # (`impermanence.nixosModules.impermanence` in
        # `commonNixosModules`), so we only add the persistence map
        # itself here.
        ++ (lib.optionals cfg.impermanence [
          (root + "/modules/home/persistence.nix")
        ])
        # 3. Host-folder HM module (if home.nix exists).
        ++ hostHomeImports
        # 5. Per-profile HM extras.
        ++ cfg.extraHomeImports;
    };
  };

  # ── 5. Platform module (selected by `hypervisor`) ─────────────
  # Owns root FS, bootloader, and any platform-specific quirks.
  # Bare-metal (`hypervisor = "none"`) leaves this empty; the host
  # folder + a disko layout supply the equivalent.
  hypervisorModules =
    if cfg.hypervisor == "qemu"
    then [
      (root + "/nixos/platforms/vm-qemu.nix")
      {
        virtualisation.vmVariant.virtualisation.graphics = cfg.graphics;
      }
    ]
    else if cfg.hypervisor == "wsl"
    then [
      nixos-wsl.nixosModules.default
      (root + "/nixos/platforms/wsl.nix")
    ]
    else if cfg.hypervisor == "none"
    then []
    else throw "unknown hypervisor for profile ${name}: ${cfg.hypervisor} (expected qemu|wsl|none)";

  # Bare-metal impermanence: wipe-root is a btrfs subvolume rollback
  # in initrd, paired with the btrfs disko layout. VM profiles use
  # tmpfs `/` via vm-qemu.nix instead and don't load this module.
  wipeRootModules =
    lib.optional
    (cfg.impermanence && cfg.hypervisor == "none")
    (root + "/nixos/modules/wipe-root.nix");
in
  lib.nixosSystem {
    inherit system;
    specialArgs = {inherit plasma-manager;};
    modules =
      commonNixosModules
      ++ hostNixosImports
      ++ cfg.extraNixosImports
      ++ [profileWiring]
      ++ wipeRootModules
      ++ hypervisorModules;
  }
