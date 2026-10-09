# Whole HM side for nixos-rpi (`homeBaseline = false`). Fish + ns come
# system-wide from commonNixosModules, so nothing else is needed yet.
{...}: {
  home.stateVersion = "25.11";
}
