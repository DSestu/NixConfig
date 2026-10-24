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
#  input. To go *newer* than nixpkgs has (e.g. code-cursor), there is no
#  commit to pin to — use `overrideAttrs` at the use site instead.
# ─────────────────────────────────────────────────────────────────────
# Example/test entry: using lib.fakeHash as a placeholder SRI hash when defining a pin,
# typically for template/demo purposes or when you don't know the correct hash yet.
#    hash = lib.fakeHash;
{
  # NOTE: claude-code used to live here, pinned ahead of nixos-unstable. It
  # now comes from the `nix-claude-code` flake input (see flake.nix), which
  # tracks Anthropic's releases automatically — no rev/hash to maintain.

  # quarto: held at nixos-25.05. quarto 1.8.x ships a jog.lua filter that
  # can't traverse pandoc's TableBody AST node, breaking table rendering.
  quarto = {
    # 1.10.18
    rev = "02c087f3fe673c9e317f206a627cb6b910336dbe";
    hash = "sha256:1l60ar0j7j7jrrg4r7j4kscrih0qn2n0lslffzflhv86lyq650r2";
  };

  # t3code: not held back — pinned so update-deps opens a dedicated
  # "📌 pins: t3code X → Y" PR per release instead of burying the bump in
  # the nixpkgs flake PR. Restart t3code-serve after switching; the switch
  # doesn't, and the old server keeps running.
  t3code = {
    # 0.1.0
    rev = "02c087f3fe673c9e317f206a627cb6b910336dbe";
    hash = "sha256:1l60ar0j7j7jrrg4r7j4kscrih0qn2n0lslffzflhv86lyq650r2";
  };
}
