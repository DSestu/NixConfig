# Used only when `nixos-rebuild` runs *without* `--flake` (NIX_PATH entry
# `nixos-config`). This repo is fully defined in flake.nix; do not use this file
# as the real system config — it always fails on purpose with a clear message.
{...}: {
  assertions = [
    {
      assertion = false;
      message = ''
        This system is defined only as a flake (see flake.nix).

        From the VM (with the 9p share mounted), run:
          sudo nixos-rebuild switch --flake /mnt/hmconfig#vm

        If you symlink the checkout: sudo ln -sfn /mnt/hmconfig /etc/nixos
          sudo nixos-rebuild switch --flake /etc/nixos#vm
      '';
    }
  ];
}
