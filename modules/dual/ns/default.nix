# Dual (Home Manager + NixOS) module packaging the `ns` throwaway-shell
# command so it can be shared: expose it from a flake as
# `homeManagerModules.ns` / `nixosModules.ns`, import it, and set
# `programs.ns.enable = true`. See docs/spec-ephemeral-shells.md and
# ./README.md (how to use ns.fish in an arbitrary, non-Nix fish).
#
# The whole command lives in ./ns.fish (a complete `function ns … end` file).
# Both schemas install that same file; HM writes it under
# ~/.config/fish/functions/, NixOS ships it as a fish vendor_functions.d
# entry. Tide theming is optional and gated on `tideBadges.enable`.
{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  schema = import ../../_schema-detect.nix {inherit options;};
  inherit (schema) isHM isNixOS;
  cfg = config.programs.ns;

  # The complete `function ns … end` file, installed verbatim on both schemas
  # and usable as a drop-in for any fish (see README).
  nsFunctionText = builtins.readFile ./ns.fish;

  # Register `ns` with the ctrl+f function browser (browse_functions in
  # modules/dual/fish.nix reads this global in addition to its own list).
  # Sourced from conf.d at every shell start; `set -ga` appends per session.
  browseSnippet = "set -ga __user_browse_functions ns\n";

  # Runtime dependencies. Each is annotated with which part of `ns` needs it.
  # `nix` (live mode + package injection) is assumed already present on a Nix
  # host and is intentionally not added here. coreutils is ubiquitous.
  runtimeDeps = with pkgs;
    [
      bubblewrap # bwrap sandbox for the `ns` command (! isolated / @ rehearse)
      git # `ns <url>` clone, for the `ns` command
      util-linux # findmnt, used by `ns @` (rehearse) to enumerate mounts
    ]
    ++ cfg.extraPackages;

  # extraPackages are put on PATH inside every ns shell (isolated hides the
  # real profile, so they must be injected). The command wraps bwrap in
  # `nix shell $__ns_extra_refs …`; we hand it the flake refs via conf.d.
  # `lib.getName` derives the nixpkgs attr from each package (fine for the
  # common case; unusual pname≠attr packages may need requesting by name).
  nsExtraRefs = map (p: "nixpkgs#" + lib.getName p) cfg.extraPackages;
  nsExtraConf = "set -gx __ns_extra_refs " + lib.concatStringsSep " " nsExtraRefs + "\n";
  hasExtra = cfg.extraPackages != [];

  # Optional Tide prompt integration (badges + per-mode accents), loaded from
  # conf.d after the base theme and before Tide bakes. See ./ns-tide.fish.
  tideConfText = builtins.readFile ./ns-tide.fish;

  # NixOS: ship ns.fish + the browse snippet (+ tide conf when enabled) under
  # the profile's fish vendor dirs — the only system-wide paths Nix-built fish
  # auto-scans.
  nsSystemPkg = pkgs.symlinkJoin {
    name = "fish-ns";
    paths =
      [
        (pkgs.writeTextFile {
          name = "fish-fn-ns";
          destination = "/share/fish/vendor_functions.d/ns.fish";
          text = nsFunctionText;
        })
        (pkgs.writeTextFile {
          name = "fish-conf-ns-browse";
          destination = "/share/fish/vendor_conf.d/10-ns-browse.fish";
          text = browseSnippet;
        })
      ]
      ++ lib.optional cfg.tideBadges.enable (pkgs.writeTextFile {
        name = "fish-conf-ns-tide";
        destination = "/share/fish/vendor_conf.d/20-ns-tide.fish";
        text = tideConfText;
      })
      ++ lib.optional hasExtra (pkgs.writeTextFile {
        name = "fish-conf-ns-extra";
        destination = "/share/fish/vendor_conf.d/11-ns-extra.fish";
        text = nsExtraConf;
      });
  };
in {
  options.programs.ns = {
    enable = lib.mkEnableOption "the `ns` throwaway-shell command (live / ! isolated / @ rehearse)";
    tideBadges.enable = lib.mkEnableOption "Tide prompt badges and per-mode color accents for `ns`";
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      example = lib.literalExpression "[ pkgs.jq ]";
      description = "Extra packages made available on PATH inside every `ns` shell.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.optionalAttrs isHM {
      home.packages = runtimeDeps;
      xdg.configFile =
        {
          "fish/functions/ns.fish".text = nsFunctionText;
          "fish/conf.d/10-ns-browse.fish".text = browseSnippet;
        }
        // lib.optionalAttrs cfg.tideBadges.enable {
          "fish/conf.d/20-ns-tide.fish".source = ./ns-tide.fish;
        }
        // lib.optionalAttrs hasExtra {
          "fish/conf.d/11-ns-extra.fish".text = nsExtraConf;
        };
    })
    (lib.optionalAttrs isNixOS {
      environment.systemPackages = runtimeDeps ++ [nsSystemPkg];
    })
  ]);
}
