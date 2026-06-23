{
  lib,
  options,
  pkgs,
  ...
}: let
  inherit (import ../_schema-detect.nix {inherit options;}) isHM isNixOS;
  commonPackages = with pkgs; [
    google-chrome
    brave
    remmina
    btop
  ];
in {
  config = lib.mkMerge [
    (lib.optionalAttrs isHM {
      home.packages = commonPackages;
    })
    (lib.optionalAttrs isNixOS {
      environment.systemPackages = commonPackages;
    })
  ];
}
