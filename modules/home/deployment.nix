{
  pkgs,
  ...
}: {
  # Tools for installing/updating remote NixOS systems from this machine.
  # `nixos-anywhere` does first-install (or full reprovision) over SSH.
  # Pair it with `disko` for declarative partitioning — disko is used
  # ad-hoc via `nix run github:nix-community/disko` and doesn't need to
  # live in PATH. See readme → "Remote install/reprovision (nixos-anywhere)".
  home.packages = with pkgs; [
    nixos-anywhere
  ];
}
