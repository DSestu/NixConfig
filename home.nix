{
  config,
  pkgs,
  ...
}: {
  home.username = "david";
  home.homeDirectory = "/home/david";

  home.stateVersion = "25.11";

  # On non-NixOS hosts — critical for GUI integration:
  targets.genericLinux.enable = true;

  programs.fish.enable = true;

  home.packages = [
  ];

  home.file = {
  };

  home.sessionVariables = {
  };

  programs.home-manager.enable = true;
}
