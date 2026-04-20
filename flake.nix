{
  description = "Home Manager configuration of david";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    homeConfigurations."david" = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      modules = [
        ./home.nix
        # On non-NixOS hosts — critical for GUI integration:
        {targets.genericLinux.enable = true;}
      ];
    };

    nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./nixos/vm.nix
        ./modules/kde.nix
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "bak";
            users.david = import ./home.nix;
          };
        }
      ];
    };
  };
}
