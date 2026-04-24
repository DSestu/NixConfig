{
  pkgs,
  ...
}: {
  nixpkgs.config.allowUnfree = true;

  imports = [
    ../modules/network.nix
  ];

  # Required when using home.persistence (impermanence): keeps assigned
  # uids/gids stable across reboots instead of re-randomizing from /etc/passwd.
  environment.persistence."/nix/persist" = {
    directories = ["/var/lib/nixos"];
  };

  services.xserver.xkb.layout = "fr";
  console.keyMap = "fr";

  users.users.david = {
    isNormalUser = true;
    initialPassword = "nixos";
    extraGroups = ["wheel"];
    shell = pkgs.fish;
  };

  services.openssh.enable = true;
  # System-wide fish shell
  programs.fish.enable = true;

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
    persistent = true;
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "david";
  };

  environment.systemPackages = [];

  system.stateVersion = "25.11";
}
