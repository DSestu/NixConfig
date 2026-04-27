{
  lib,
  options,
  pkgs,
  ...
}: let
  gamingPackages = with pkgs; [
    steam
    gdlauncher-carbon
  ];
in {
  config = lib.mkMerge [
    (lib.optionalAttrs (options ? home) {
      home.packages = gamingPackages;
    })
    (lib.optionalAttrs (options ? environment && options.environment ? systemPackages) {
      environment.systemPackages = gamingPackages;
    })
  ];
}
