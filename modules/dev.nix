{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    devenv
    direnv
    vscode
    code-cursor
    uv
  ];
}
