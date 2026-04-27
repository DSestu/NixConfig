{plasma-manager, ...}: {
  # NixOS module for KDE desktop stack.
  imports = [./kde/kde.nix];

  config = {
    # Plasma Manager module is required for both plasma and plasma applet config.
    home-manager.sharedModules = [
      plasma-manager.homeModules.plasma-manager
    ];

    # Keep files separate; only orchestration is centralized here.
    home-manager.users.david.imports = [
      ./kde/plasma.nix
      ./kde/plasma-appletsrc.nix
      ./kde/konsole.nix
    ];
  };
}
