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
  #   # Re-encrypt all secrets for the new host (run from THIS directory)
  #   cd secrets
  #   RULES=./secrets.nix nix run github:ryantm/agenix -- --rekey -i ~/.ssh/id_ed25519
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
  nixos-vm-headless = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICSHuZAfBBaPU/9gf3zhmI7bFODqwJdvnPiVUhFXwRjF nixos-vm-headless";
  nixos-wsl = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBlMZ3Q2ilo1Aiae6Dkwz2Xr86IMnNGfaBqd7aSJufhc nixos-wsl";
  karlizen = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMfqazQyxSN1UCEb11H1prRLHil0mu2Z7wWBqqxOVgHx david.sestu@gmail.com";

  # David's current user key (~/.ssh/id_ed25519 on nixos-wsl). Distinct from
  # `karlizen` above — kept as its own recipient so a rekey can be driven from
  # whichever machine holds either key.
  david-user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMckPqNrF5yUrNoAA362P04Pm13leteSatYQ+4c+3Fxk david.sestu@gmail.com";

  allHosts = [
    # nixos-desktop
    nixos-vm
    nixos-vm-headless
    nixos-wsl
    karlizen
    david-user
  ];
in {
  # ── ALWAYS run agenix from THIS directory ────────────────────────────────
  # agenix resolves both the FILE argument and $RULES relative to the
  # current working directory — NOT relative to this file. Run it from the
  # repo root and `-e my-secret.age` silently creates `./my-secret.age` at
  # the repo root, while `--rekey` reports "<file> wasn't created" for every
  # secret. `RULES=secrets.nix` also fails: Nix needs an explicit path, so
  # it must be `RULES=./secrets.nix`. Hence: `cd secrets` first, always.
  #
  # On a NixOS host `ragenix` is on PATH (nixos/modules/secrets.nix). It is a
  # drop-in for `--rekey`, but the two tools differ in two ways that matter:
  #
  #                    agenix (bash, via nix run)   ragenix (Rust, on PATH)
  #   path resolution  relative to your CWD         relative to the rules file
  #   piping a value   automatic when stdin is      needs an explicit
  #                    not a tty                    EDITOR='cp -- /dev/stdin'
  #
  # `cd secrets` + `RULES=./secrets.nix` is correct for BOTH, which is why
  # every recipe below uses it. (ragenix's rules-relative behaviour is also
  # why githooks/pre-commit can legitimately run it from the repo root.)
  # ─────────────────────────────────────────────────────────────────────────
  #
  # ── How to add a new secret ───────────────────────────────────────────────
  # 1. Declare it below with the hosts that need to decrypt it:
  #      "my-secret.age".publicKeys = allHosts;
  #
  # 2. Create the encrypted file. PREFER PIPING — when stdin is not a
  #    terminal, agenix ignores $EDITOR and does `cp -- /dev/stdin`, so the
  #    value lands byte-for-byte with exactly one trailing newline and no
  #    editor can sneak in a blank line:
  #      cd secrets
  #      printf '%s\n' 'the-secret-value' \
  #        | RULES=./secrets.nix nix run github:ryantm/agenix -- -e my-secret.age -i ~/.ssh/id_ed25519
  #
  #    Or generate it in place, never seeing the value at all:
  #      nix shell nixpkgs#mkpasswd --command mkpasswd -m yescrypt \
  #        | RULES=./secrets.nix nix run github:ryantm/agenix -- -e my-secret.age -i ~/.ssh/id_ed25519
  #
  #    With ragenix, the same pipe needs the editor spelled out:
  #      printf '%s\n' 'the-secret-value' \
  #        | EDITOR='cp -- /dev/stdin' RULES=./secrets.nix ragenix -e my-secret.age -i ~/.ssh/id_ed25519
  #
  #    For a genuinely multi-line secret, an editor is fine (stdin is a tty,
  #    so $EDITOR is honoured) — just don't leave a trailing blank line:
  #      cd secrets
  #      EDITOR=nano RULES=./secrets.nix nix run github:ryantm/agenix -- -e my-secret.age -i ~/.ssh/id_ed25519
  #
  #    Verify the shape afterwards (single-line secrets should print 1):
  #      nix shell nixpkgs#age --command age -d -i ~/.ssh/id_ed25519 my-secret.age | wc -l
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
  #
  # ── Rekey after changing the recipient list ───────────────────────────────
  #      cd secrets
  #      RULES=./secrets.nix nix run github:ryantm/agenix -- --rekey -i ~/.ssh/id_ed25519
  #
  # `githooks/pre-commit` does this for you whenever this file is part of a
  # commit (enable once per clone: `git config core.hooksPath githooks`).
  # ─────────────────────────────────────────────────────────────────────────
  "tailscale-auth-key.age".publicKeys = allHosts; # See how it is used in modules/home/network.nix
  "david-password.age".publicKeys = allHosts;
  "cachix-auth-token.age".publicKeys = allHosts; # Consumed by the `cachix` wrapper in modules/dual/fish.nix
}
