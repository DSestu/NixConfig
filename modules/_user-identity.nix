# Single source of truth for the user's identity across the flake.
# Consumed by modules that need a git committer, a tailscale account
# expectation, or anything else identifying. Import via:
#
#   let identity = import ../_user-identity.nix; in ...
#
# Same path works from `modules/home/` and `modules/dual/` because
# both live one level under `modules/`.
{
  gitName = "DSestu";
  gitEmail = "david.sestu@gmail.com";
  tailscaleAccount = "david.sestu@gmail.com";
}
