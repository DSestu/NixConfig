{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    devenv
    direnv
  ];
}
