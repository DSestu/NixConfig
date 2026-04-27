{
  description = "Home Manager configuration of david";

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
      # Baseline applied to every profile. The `disko` module is inert
      # unless a profile sets `disko.devices` (typically by importing one
      # of `nixos/disko/single-disk-{uefi,bios}.nix` from its host folder
      # — see readme → "Remote install/reprovision (nixos-anywhere)").
      commonNixosModules = [
        ./nixos/modules/profile-options.nix
        ./nixos/base.nix
        impermanence.nixosModules.impermanence
        home-manager.nixosModules.home-manager
        disko.nixosModules.default
      ];
      commonHomeImports = [
        ./home.nix
      ];

      # Shared desktop profile used by every graphical target.
      # Opt-in extras (like gaming) are added per-profile below.
      sharedDesktopProfile = {
        graphics = true;
        extraNixosModules = [./modules/kde-suite.nix];
      };

      # Profile dictionary: add/remove modules per target here.
      profiles = {
        nixos-vm =
          sharedDesktopProfile
          // {
            hostname = "nixos-vm";
            hypervisor = "qemu";
            impermanence = true;
            extraHomeImports = [./modules/gaming.nix];
          };

        nixos-desktop =
          sharedDesktopProfile
          // {
            hostname = "nixos-desktop";
            hypervisor = "none";
            extraHomeImports = [./modules/gaming.nix];
            impermanence = true;
          };

        nixos-vm-headless = {
          hostname = "nixos-vm-headless";
          hypervisor = "qemu";
          graphics = false;
          impermanence = true;
        };

        nixos-vbox =
          sharedDesktopProfile
          // {
            hostname = "nixos-vbox";
            hypervisor = "virtualbox";
            impermanence = true;
          };

        nixos-wsl = {
          hostname = "nixos-wsl";
          hypervisor = "wsl";
          # Keep disabled by default to avoid accidental ephemeral behavior.
          # This also guarantees no interaction with the Windows host FS.
          impermanence = false;
          extraHomeImports = [
            ./modules/wsl-home.nix
            ./nixos/hosts/nixos-wsl/fish.nix
          ];
        };
      };

      mkProfile = name: profile: let
        cfg =
          {
            graphics = true;
            extraNixosModules = [];
            extraHomeImports = [];
            impermanence = false;
          }
          // profile;

        # Auto-discovered per-profile overrides in nixos/hosts/<profile-name>/.
        # The directory is the home for host-specific modules (e.g.
        # hardware-configuration.nix on bare metal). Picked up automatically
        # when default.nix exists; no flake wiring required.
        hostDir = ./nixos/hosts + "/${name}";
        hostModules = lib.optional (builtins.pathExists (hostDir + "/default.nix")) hostDir;

        profileWiring = {
          networking.hostName = cfg.hostname;
          profiles.impermanence.enable = cfg.impermanence;
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "bak";
            users.david.imports =
              commonHomeImports
              ++ (lib.optional cfg.impermanence ./modules/persistence.nix)
              ++ cfg.extraHomeImports;
          };
        };

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
            commonNixosModules
            ++ hostModules
            ++ cfg.extraNixosModules
            ++ [profileWiring]
            ++ hypervisorModules;
        };
    in
      lib.mapAttrs mkProfile profiles;
  };
}
