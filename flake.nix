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
      mkVm = {graphics}:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./nixos/vm.nix
            ./modules/kde.nix
            impermanence.nixosModules.impermanence
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "bak";
                sharedModules = [plasma-manager.homeModules.plasma-manager];
                users.david.imports = [
                  ./home.nix
                  ./modules/plasma.nix
                  ./modules/plasma-appletsrc.nix
                  ./modules/konsole.nix
                  ./modules/persistence.nix
                ];
              };
            }
            {
              virtualisation.vmVariant.virtualisation.graphics = graphics;
            }
          ];
        };
    in {
      vm = mkVm {graphics = true;};
      vm-headless = mkVm {graphics = false;};
    };
  };
}
