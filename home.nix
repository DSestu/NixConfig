{
  config,
  pkgs,
  ...
}: {
  imports = [
    # ./modules/fish.nix
  ];

  home.username = "david";
  home.homeDirectory = "/home/david";

  home.stateVersion = "25.11";

  # On non-NixOS hosts — critical for GUI integration:
  targets.genericLinux.enable = true;

  home.packages = with pkgs; [
    fish
    neovim
  ];

  home.file = {
  };

  home.sessionVariables = {
  };

  programs.home-manager.enable = true;
}
