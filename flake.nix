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
  };

  outputs = {
    nixpkgs,
    home-manager,
    plasma-manager,
    impermanence,
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
      # Shared desktop VM profile used by both QEMU and VirtualBox targets.
      sharedDesktopVm = {
        graphics = true;
        modules = {
          kdeSuite = true;
          gaming = true;
        };
      };

      # Profile dictionary: toggle modules/features here per target.
      profiles = {
        nixos-vm =
          sharedDesktopVm
          // {
            hostname = "nixos-vm";
            hypervisor = "qemu";
          };

        nixos-desktop =
          sharedDesktopVm
          // {
            hostname = "nixos-desktop";
            hypervisor = "none";
          };

        nixos-vm-headless = {
          hostname = "nixos-vm-headless";
          hypervisor = "qemu";
          graphics = false;
          modules = {
            kdeSuite = false;
            gaming = false;
          };
        };

        nixos-vbox =
          sharedDesktopVm
          // {
            hostname = "nixos-vbox";
            hypervisor = "virtualbox";
          };
      };

      profileDefaults = {
        hostname = "nixos-vm";
        hypervisor = "qemu";
        graphics = true;
        modules = {
          kdeSuite = true;
          gaming = false;
        };
      };

      mkProfile = name: profile: let
        cfg = lib.recursiveUpdate profileDefaults profile;
        commonModules = [
          ./nixos/base.nix
          # Always enabled on every profile.
          impermanence.nixosModules.impermanence
          home-manager.nixosModules.home-manager
          {
            networking.hostName = cfg.hostname;
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "bak";
              users.david.imports = [
                ./modules/persistence.nix
                ./home.nix
              ] ++ lib.optionals cfg.modules.gaming [
                ./modules/gaming.nix
              ];
            };
          }
          ./modules/kde-suite.nix
        ];

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
          else [];
      in
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            profileName = name;
            profileConfig = cfg;
            inherit plasma-manager;
          };
          modules = commonModules ++ hypervisorModules;
        };
    in
      lib.mapAttrs mkProfile profiles;
  };
}
