let
  # Host SSH public keys.
  #
  # For an existing machine:
  #   cat /etc/ssh/ssh_host_ed25519_key.pub
  #
  # For a new machine (Option A — pre-generate before install):
  #   # Generate key pair on current machine
  #   ssh-keygen -t ed25519 -N "" -f /tmp/newhost-ssh-host-key
  #   cat /tmp/newhost-ssh-host-key.pub   # → paste below
  #
  #   # Re-encrypt all secrets for the new host (run from repo root)
  #   EDITOR=nano RULES=secrets/secrets.nix nix run github:ryantm/agenix -- --rekey -i ~/.ssh/id_ed25519
  #
  #   # Stage key for nixos-anywhere injection
  #   mkdir -p /tmp/newhost-extra-files/etc/ssh
  #   cp /tmp/newhost-ssh-host-key     /tmp/newhost-extra-files/etc/ssh/ssh_host_ed25519_key
  #   cp /tmp/newhost-ssh-host-key.pub /tmp/newhost-extra-files/etc/ssh/ssh_host_ed25519_key.pub
  #   chmod 600 /tmp/newhost-extra-files/etc/ssh/ssh_host_ed25519_key
  #
  #   # Deploy
  #   nixos-anywhere --extra-files /tmp/newhost-extra-files --flake .#nixos-newhost user@target-ip
  #
  #   # Clean up
  #   rm -rf /tmp/newhost-ssh-host-key /tmp/newhost-extra-files
  # nixos-desktop = "ssh-ed25519 AAAA... nixos-desktop";
  nixos-vm = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOz/XI3FEFVrdYOYuYl0jCyBkwXkS0rBpmAXHUpAieaE nixos-vm";

  allHosts = [
    # nixos-desktop
    nixos-vm
  ];
in {
  # ── How to add a new secret ───────────────────────────────────────────────
  # 1. Declare it below with the hosts that need to decrypt it:
  #      "my-secret.age".publicKeys = allHosts;
  #
  # 2. Create the encrypted file (opens $EDITOR, paste the secret, save):
  #      EDITOR=nano RULES=secrets/secrets.nix nix run github:ryantm/agenix -- -e my-secret.age -i ~/.ssh/id_ed25519
  #      (run from repo root; FILE is relative to secrets.nix, not the repo root)
  #
  # 3. Declare it in nixos/modules/secrets.nix:
  #      (lib.mkIf (builtins.pathExists ../../secrets/my-secret.age) {
  #        my-secret.file = ../../secrets/my-secret.age;
  #      })
  #
  # 4. Reference it anywhere in NixOS config via:
  #      config.age.secrets.my-secret.path   # → /run/agenix/my-secret
  #
  # 5. Commit both secrets/secrets.nix and secrets/my-secret.age
  # ─────────────────────────────────────────────────────────────────────────
  "tailscale-auth-key.age".publicKeys = allHosts; # See how it is used in modules/home/network.nix
  "david-password.age".publicKeys = allHosts;
}
