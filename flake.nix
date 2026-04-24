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
      mkVm = {
        graphics,
        kde ? graphics,
        hostname ? "nixos-vm",
      }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules =
            [
              ./nixos/vm.nix
              impermanence.nixosModules.impermanence
              home-manager.nixosModules.home-manager
              {
                networking.hostName = hostname;
                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  backupFileExtension = "bak";
                  sharedModules = lib.optionals kde [plasma-manager.homeModules.plasma-manager];
                  users.david.imports =
                    [
                      ./modules/persistence.nix
                      ./home.nix
                    ]
                    ++ lib.optionals kde [
                      ./modules/plasma.nix
                      ./modules/plasma-appletsrc.nix
                      ./modules/konsole.nix
                    ];
                };
              }
              {
                virtualisation.vmVariant.virtualisation.graphics = graphics;
              }
            ]
            ++ lib.optionals kde [
              ./modules/kde.nix
            ];
        };
    in {
      nixos-vm = mkVm {graphics = true;};
      nixos-vm-headless = mkVm {graphics = false; hostname = "nixos-vm-headless";};
    };
  };
}
