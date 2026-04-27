{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./modules/home/common.nix
    ./modules/common/fish.nix
    ./modules/home/dev.nix
    ./modules/home/deployment.nix
    ./modules/home/network.nix
    ./modules/home/pentest.nix
    ./modules/home/gaming.nix
  ];

  home.username = "david";
  home.homeDirectory = "/home/david";
  home.stateVersion = "25.11";

  home.packages = with pkgs; [
  ];

  fonts.fontconfig.enable = true;

  home.file = {
  };

  home.sessionVariables = {
  };

  # Breeze GTK themes reference kde-gtk-config modules (colorreload, window-decorations).
  # Without this on GTK_PATH, apps log "Failed to load module …" (common on Nix-on-non-NixOS).
  home.sessionSearchVariables = {
    GTK_PATH = ["${pkgs.kdePackages.kde-gtk-config}/lib/gtk-3.0"];
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
