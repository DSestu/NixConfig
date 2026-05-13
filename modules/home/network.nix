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
      };
    })
  ];
}
