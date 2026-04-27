{
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    steam
    gdlauncher-carbon
  ];
}
