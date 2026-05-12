Set tailscale as nixos module only.

Set pentest as home/nixos modules mixed.

Remove the mixed logic from modules/home/common.nix

Add the logic in flake.nix to have also a common home/nixos modules commons and special imports for each profile. Also add the common template in the template host folder.
