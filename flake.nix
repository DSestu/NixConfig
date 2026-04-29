{
  description = "Home Manager & NixOS configuration of David";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    impermanence.url = "github:nix-community/impermanence";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    plasma-manager,
    impermanence,
    nixos-wsl,
    disko,
    ...
  }: let
    system = "x86_64-linux";
    lib = nixpkgs.lib;
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    homeConfigurations."david" = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      modules = [
        ./home.nix
        # On non-NixOS hosts — critical for GUI integration:
        {targets.genericLinux.enable = true;}
      ];
    };

    nixosConfigurations = let
      # ═══════════════════════════════════════════════════════════════════
      #  Per-profile recipe (read this first).
      # ═══════════════════════════════════════════════════════════════════
      #
      #  Every profile in the dictionary below is built from FIVE
      #  ingredients, in this order:
      #
      #    1. commonNixosModules    — system-wide baseline (every profile)
      #    2. commonHomeImports     — user-wide baseline   (every profile)
      #    3. host folder           — auto-discovered from nixos/hosts/<name>/
      #                               (default.nix → NixOS, home.nix → HM)
      #    4. impermanence flag     — flips profiles.impermanence.enable on
      #                               and auto-adds modules/home/persistence.nix
      #    5. extras + platform     — extraNixosImports / extraHomeImports
      #                               from the profile entry, plus the
      #                               module for `hypervisor = "..."`
      #
      #  To add a profile: copy an existing entry, rename, tweak. To add
      #  per-profile config without touching this file, drop a default.nix
      #  (NixOS) or home.nix (HM) into nixos/hosts/<name>/.
      # ═══════════════════════════════════════════════════════════════════

      # ─── 1. NixOS baseline (system-wide, every profile) ──────────────
      # `disko.nixosModules.default` is loaded but inert until a host
      # folder imports one of `nixos/disko/single-disk-{uefi,bios}.nix`.
      commonNixosModules = [
        ./nixos/modules/profile-options.nix
        ./nixos/base.nix
        # Wipe-root initrd service — gated by `profiles.impermanence.enable`,
        # so it's a no-op on profiles that don't opt in. Lives here (not in a
        # platform module) so disko-based bare-metal profiles get it without
        # per-host wiring.
        ./nixos/modules/impermanence-wipe.nix
        ./modules/common/fish.nix
        impermanence.nixosModules.impermanence
        home-manager.nixosModules.home-manager
        disko.nixosModules.default
      ];

      # ─── 2. Home Manager baseline (user-wide, every profile) ─────────
      # `home.nix` aggregates all the modules under `modules/home/`.
      commonHomeImports = [
        ./home.nix
      ];

      # ─── Shared desktop profile (sugar for graphical targets) ─────────
      # Adds the KDE Plasma stack on top of the baseline. Composed via
      # `// {...}` in the profile dictionary, so individual profiles can
      # still override or append.
      sharedDesktopProfile = {
        graphics = true;
        extraNixosImports = [./modules/nixos/kde-suite.nix];
      };

      # ─── Profile dictionary ──────────────────────────────────────────
      # Each entry: { hostname, hypervisor, impermanence?, graphics?,
      #               extraNixosImports?, extraHomeImports? }
      profiles = {
        # ─────────────────────────────────────────────────────────────────
        # TEMPLATE — DO NOT EDIT, DO NOT DEPLOY.
        #
        # `_template-bare-metal` is the canonical starting point for any
        # new bare-metal profile. The leading underscore signals "skeleton
        # only" — never `nixos-rebuild` or `nixos-anywhere` against it
        # directly. Instead, copy this entry to a new key (e.g. `my-laptop`),
        # copy `nixos/hosts/_template-bare-metal/` to `nixos/hosts/my-laptop/`,
        # then customize the copy.
        #
        # What's enabled here:
        #   - `sharedDesktopProfile` → graphics on, KDE Plasma stack
        #     (via `extraNixosImports = [./modules/nixos/kde-suite.nix]`).
        #   - `hypervisor = "none"`  → no VM platform module; disko owns
        #                              partitions and the bootloader
        #                              (see the matching host folder).
        #   - `impermanence = true`  → wipe-root on every boot, persist
        #                              only what's listed in
        #                              `nixos/base.nix` (system) and
        #                              `modules/home/persistence.nix` (home).
        #   - gaming home module     → Steam, GDLauncher, etc. for the user.
        #
        # The matching `nixos/hosts/_template-bare-metal/default.nix`
        # imports the disko UEFI layout. Bootloader/disk/hardware tweaks
        # belong there, not in this dictionary.
        # ─────────────────────────────────────────────────────────────────
        #### Template bare-metal profile ####
        _template-bare-metal =
          sharedDesktopProfile
          // {
            # Placeholder hostname. The flake still evaluates with this
            # value, but you must rename when you copy this entry.
            hostname = "REPLACE-ME";
            hypervisor = "none";
            impermanence = true;
            extraHomeImports = [./modules/home/gaming.nix];
          };

        #### Bare-metal profiles ####
        nixos-desktop =
          sharedDesktopProfile
          // {
            hostname = "nixos-desktop";
            hypervisor = "none";
            extraHomeImports = [./modules/home/gaming.nix];
            impermanence = true;
          };

        #### VM's & WSL's ####
        nixos-vm =
          sharedDesktopProfile
          // {
            hostname = "nixos-vm";
            hypervisor = "qemu";
            impermanence = true;
            extraHomeImports = [./modules/home/gaming.nix];
          };

        nixos-vm-headless = {
          # No `sharedDesktopProfile` → no KDE, no graphics. Headless.
          hostname = "nixos-vm-headless";
          hypervisor = "qemu";
          graphics = false;
          impermanence = true;
        };

        # Installed into a VirtualBox VM via `nixos-anywhere` from a live ISO,
        # not built as an OVA. That makes it a bare-metal-style profile
        # (`hypervisor = "none"` → no platform module) where the host folder
        # imports a disko layout and a hardware-configuration.nix, exactly
        # like `_template-bare-metal`. The "OVA build" path
        # (`hypervisor = "virtualbox"` → `vm-virtualbox.nix` →
        # `virtualbox-image.nix`) declares `fileSystems."/"` itself and
        # would collide with disko — see CONTRIBUTING.md "Where to look first
        # when something breaks".
        nixos-vbox =
          sharedDesktopProfile
          // {
            hostname = "nixos-vbox";
            hypervisor = "none";
            impermanence = true;
          };

        nixos-wsl = {
          hostname = "nixos-wsl";
          hypervisor = "wsl";
          # Keep disabled by default to avoid accidental ephemeral behavior.
          # This also guarantees no interaction with the Windows host FS.
          impermanence = false;
          # WSL-specific HM tweaks. The host-folder home.nix (auto-discovered
          # below) handles the per-profile fish overrides.
          extraHomeImports = [./modules/home/wsl-home.nix];
        };
      };

      # ─── mkProfile: assembles a single profile into a nixosSystem ────
      mkProfile = name: profile: let
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
        # touching this file. Each can `imports = [./nixos/...]` or
        # `imports = [./home/...]` to organize per-host sub-modules.
        hostDir = ./nixos/hosts + "/${name}";
        hostNixosImports =
          lib.optional (builtins.pathExists (hostDir + "/default.nix")) hostDir;
        hostHomeImports =
          lib.optional (builtins.pathExists (hostDir + "/home.nix"))
          (hostDir + "/home.nix");

        ########### PROFILE WIRING ###########
        # ── Profile wiring (translates the profile entry into config) ──
        # Home-wise config, home-manager wiring. Impermanence wiring is handled by the profile-options module.
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
              # The HM module from the impermanence flake has to come along
              # too — without it `home.persistence` is silently accepted by
              # home-manager's freeform option type and produces no
              # symlinks/binds, so e.g. fish_history evaporates on reboot.
              ++ (lib.optionals cfg.impermanence [
                impermanence.homeManagerModules.impermanence
                ./modules/home/persistence.nix
              ])
              # 3. Host-folder HM module (if home.nix exists).
              ++ hostHomeImports
              # 5. Per-profile HM extras.
              ++ cfg.extraHomeImports;
          };
        };


        ########### HYPERVISOR MODULES / SYSTEM CONFIGURATION ###########
        # ── 5. Platform module (selected by `hypervisor`) ─────────────
        # Owns root FS, bootloader, and any platform-specific quirks.
        # Bare-metal (`hypervisor = "none"`) leaves this empty; the host
        # folder + a disko layout supply the equivalent.
        hypervisorModules =
          if cfg.hypervisor == "qemu"
          then [
            ./nixos/platforms/vm-qemu.nix
            {
              virtualisation.vmVariant.virtualisation.graphics = cfg.graphics;
            }
          ]
          else if cfg.hypervisor == "virtualbox"
          then [
            ./nixos/platforms/vm-virtualbox.nix
          ]
          else if cfg.hypervisor == "wsl"
          then [
            nixos-wsl.nixosModules.default
            ./nixos/platforms/wsl.nix
          ]
          else [];
      in
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {inherit plasma-manager;};
          modules =
            # 1. Common NixOS baseline.
            commonNixosModules
            # 3. Host-folder NixOS module (if default.nix exists).
            ++ hostNixosImports
            # 5. Per-profile NixOS extras.
            ++ cfg.extraNixosImports
            # 2/4. Profile wiring + impermanence + HM imports.
            ++ [profileWiring]
            # 5. Platform module.
            ++ hypervisorModules;
        };
    in
      lib.mapAttrs mkProfile profiles;
  };
}
