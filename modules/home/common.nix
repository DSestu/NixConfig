{
  lib,
  options,
  pkgs,
  ...
}: let
  commonPackages = with pkgs; [
    google-chrome
    brave
  ];
in {
  config = lib.mkMerge [
    (lib.optionalAttrs (options ? home) {
      home.packages = commonPackages;
    })
    (lib.optionalAttrs (options ? environment && options.environment ? systemPackages) {
      environment.systemPackages = commonPackages;
    })
  ];
}
