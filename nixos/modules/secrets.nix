# Declarative secret declarations via agenix.
# Each secret is guarded by `pathExists` so profiles that don't have
# a given .age file committed yet build without errors.
# To add a secret:
#   1. Add its public keys to secrets/secrets.nix
#   2. Run: nix run github:ryantm/agenix -- -e secrets/<name>.age
#   3. Declare it below and reference config.age.secrets.<name>.path
{
  config,
  lib,
  pkgs,
  ...
}: {
  environment.systemPackages = [pkgs.ragenix];

  age.secrets = lib.mkMerge [
    (lib.mkIf (builtins.pathExists ../../secrets/tailscale-auth-key.age) {
      tailscale-auth-key.file = ../../secrets/tailscale-auth-key.age;
    })
    (lib.mkIf (builtins.pathExists ../../secrets/david-password.age) {
      david-password.file = ../../secrets/david-password.age;
    })
  ];
}
