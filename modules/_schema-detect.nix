# Schema detection for dual-schema modules — files that need to be
# loadable as both NixOS modules (at system level) and Home Manager
# modules (at user level), branching their contributions based on
# which evaluator is asking.
#
# Use:
#
#   { options, ... }: let
#     schema = import ../_schema-detect.nix { inherit options; };
#   in {
#     config = lib.mkMerge [
#       (lib.optionalAttrs schema.isHM     { home.packages = ...; })
#       (lib.optionalAttrs schema.isNixOS  { environment.systemPackages = ...; })
#     ];
#   }
#
# The two predicates are mutually exclusive: HM modules expose
# `options.home`; NixOS modules expose `options.environment`. A
# module that finds neither is being misused.
{options}: {
  isHM = options ? home;
  isNixOS = options ? environment && options.environment ? systemPackages;
}
