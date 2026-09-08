# Declarative secret declarations via agenix.
# Each secret is guarded by `pathExists` so profiles that don't have
# a given .age file committed yet build without errors.
# To add a secret:
#   1. Add its public keys to secrets/secrets.nix
#   2. From the secrets/ directory (agenix resolves paths relative to CWD,
#      so running this from the repo root writes the file in the wrong
#      place), pipe the value in rather than using an editor:
#        cd secrets
#        printf '%s\n' 'the-value' \
#          | RULES=./secrets.nix nix run github:ryantm/agenix -- -e <name>.age -i ~/.ssh/id_ed25519
#   3. Declare it below and reference config.age.secrets.<name>.path
#
# See the header of secrets/secrets.nix for the full workflow.
{
  config,
  lib,
  pkgs,
  ...
}: {
  environment.systemPackages = [pkgs.ragenix];

  # Identity used to DECRYPT secrets at boot — the host's own SSH key.
  #
  # agenix defaults to ["/etc/ssh/ssh_host_rsa_key"
  # "/etc/ssh/ssh_host_ed25519_key"], which is wrong on an impermanent
  # host: `/` (and therefore `/etc`) is tmpfs, and the `agenixInstall`
  # activation snippet runs before the host keys are available there. The
  # result is a silent cascade — every secret fails to decrypt:
  #
  #   [agenix] WARNING: config.age.identityPaths entry
  #            /etc/ssh/ssh_host_ed25519_key not present!
  #   [agenix] WARNING: no readable identities found!
  #   Activation script snippet 'agenixInstall' failed (1)
  #   warning: password file ‘/run/agenix/david-password’ does not exist
  #
  # …and `users.users.david.hashedPasswordFile` then points at a file that
  # doesn't exist, so the account has NO valid password and every login is
  # rejected with no obvious reason.
  #
  # /nix/persist is on the real filesystem (ext4 `/nix` on VMs, the
  # `@persist` btrfs subvolume on bare metal) and is mounted before
  # activation, so reading the key from there works regardless of when
  # impermanence gets around to bind-mounting it into /etc. The /etc path
  # is kept as a second entry so a host that does have it there still
  # works; agenix warns about whichever entry is missing and proceeds
  # with the one it can read.
  age.identityPaths = lib.mkIf config.profiles.impermanence.enable [
    "/nix/persist/etc/ssh/ssh_host_ed25519_key"
    "/etc/ssh/ssh_host_ed25519_key"
  ];

  age.secrets = lib.mkMerge [
    (lib.mkIf (builtins.pathExists ../../secrets/tailscale-auth-key.age) {
      tailscale-auth-key.file = ../../secrets/tailscale-auth-key.age;
    })
    (lib.mkIf (builtins.pathExists ../../secrets/david-password.age) {
      david-password.file = ../../secrets/david-password.age;
    })
    # `owner` matters here: unlike the other two secrets, this one is read
    # by an unprivileged interactive shell (the `cachix` wrapper in
    # modules/dual/fish.nix), not by a root-run service. agenix defaults to
    # root:root 0400, which the wrapper could not read.
    (lib.mkIf (builtins.pathExists ../../secrets/cachix-auth-token.age) {
      cachix-auth-token = {
        file = ../../secrets/cachix-auth-token.age;
        owner = "david";
        mode = "0400";
      };
    })
  ];
}
