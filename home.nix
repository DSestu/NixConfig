{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./modules/fish.nix
    ./modules/dev.nix
  ];

  home.username = "david";
  home.homeDirectory = "/home/david";
  home.stateVersion = "25.11";

  home.packages = with pkgs; [
    git
    nerd-fonts.meslo-lg
  ];

  fonts.fontconfig.enable = true;

  home.file = {
  };

  home.sessionVariables = {
  };

  programs.home-manager.enable = true;
  programs.fish.enable = true;

  # User-level store cleanup (current user's profiles only). Complements
  # system nix.gc on NixOS; on standalone Nix + HM this is the main scheduled GC.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
}
