# Per-profile Home Manager entry for `nixos-wsl`.
# Auto-discovered by `mkProfile` in `flake.nix` (looked up at
# `nixos/hosts/<profile-name>/home.nix`). Imports HM sub-modules
# under `./home/` so per-host user config stays grouped here.
{...}: {
  imports = [
    ./home/fish.nix
  ];
}
