{
  lib,
  profileConfig ? {},
  plasma-manager,
  ...
}: let
  moduleFlags = profileConfig.modules or {};
  enableKdeSuite = moduleFlags.kdeSuite or false;
in {
  # NixOS module for KDE desktop stack.
  imports = lib.optionals enableKdeSuite [./kde/kde.nix];

  config = {
    # Plasma Manager module is required for both plasma and plasma applet config.
    home-manager.sharedModules =
      lib.optionals enableKdeSuite [
        plasma-manager.homeModules.plasma-manager
      ];

    # Keep files separate; only orchestration is centralized here.
    home-manager.users.david.imports =
      lib.optionals enableKdeSuite [./kde/plasma.nix]
      ++ lib.optionals enableKdeSuite [./kde/plasma-appletsrc.nix]
      ++ lib.optionals enableKdeSuite [./kde/konsole.nix];
  };
}
