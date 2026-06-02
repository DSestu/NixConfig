{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  inherit (import ../_schema-detect.nix {inherit options;}) isHM isNixOS;
in {
  config = lib.mkMerge [
    # Home Manager: make tailscale CLI available.
    (lib.optionalAttrs isHM {
      home.packages = with pkgs; [
        tailscale
      ];
    })

    # NixOS: run tailscaled as a system service.
    (lib.optionalAttrs isNixOS {
      services.tailscale = {
        enable = true;
        openFirewall = true;
        # If false, does nothing. Condition is if tailscale-auth-key is defined in the secrets.
        authKeyFile =
          lib.mkIf (config.age.secrets ? tailscale-auth-key)
          config.age.secrets.tailscale-auth-key.path;
      };
    })
  ];
}
