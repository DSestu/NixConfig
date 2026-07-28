{lib, ...}:
# ─────────────────────────────────────────────────────────────────────
#  System-wide version pins.
#
#  One entry per package you want to hold at a specific nixpkgs revision,
#  independent of the main `nixpkgs` input. This is the SINGLE place to
#  see every such pin — the uv/astral-style pin table for this config,
#  except each entry names the nixpkgs commit that ships the version you
#  want. Find that commit at:
#    • https://www.nixhub.io
#    • https://lazamar.co.uk/nix-versions
#
#  Each entry maps a package attribute name to a nixpkgs commit + the
#  hash of its unpacked source tree:
#
#    <pkgAttr> = { rev = "<40-char nixpkgs commit>"; hash = "<sri hash>"; };
#
#  Get the hash with (nix also prints the correct value on mismatch):
#    nix-prefetch-url --unpack \
#      https://github.com/NixOS/nixpkgs/archive/<rev>.tar.gz
#
#  flake.nix turns this table into a single overlay (`pinsOverlay`), so a
#  pinned `foo` is used everywhere `pkgs.foo` is referenced — both in the
#  Home Manager `pkgs` and in every NixOS profile's `nixpkgs.overlays`.
#
#  NOTE: this pins a package to an *older/different* nixpkgs than the main
#  input. To go *newer* than nixpkgs has (e.g. gh-stack), there is no
#  commit to pin to — use `overrideAttrs` at the use site instead.
# ─────────────────────────────────────────────────────────────────────
# Example/test entry: using lib.fakeHash as a placeholder SRI hash when defining a pin,
# typically for template/demo purposes or when you don't know the correct hash yet.
#    hash = lib.fakeHash;
{
  # quarto: held at nixos-25.05. quarto 1.8.x ships a jog.lua filter that
  # can't traverse pandoc's TableBody AST node, breaking table rendering.
  quarto = {
    # 1.7.34
    rev = "5d6bdbddb4695a62f0d00a3620b37a15275a5093";
    hash = "sha256:0yih1ll0kihp675622q3l201j527y8841lsw4n4axc1n9152jm4f";
  };
}
