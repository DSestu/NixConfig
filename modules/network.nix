{
  config,
  lib,
  options,
  pkgs,
  ...
}: {
  config = lib.mkMerge [
    # Home Manager: make tailscale CLI available.
    (lib.optionalAttrs (options ? home) {
      home.packages = with pkgs; [
        tailscale
      ];
    })

    # NixOS: run tailscaled as a system service.
    (lib.optionalAttrs (options ? services && options.services ? tailscale) {
      services.tailscale = {
        enable = true;
        openFirewall = true;
      };
    })
  ];
}
