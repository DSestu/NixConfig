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
    tig # git show | tig
  ];

  programs.git = {
    enable = true;
    userName = "DSestu";
    userEmail = "david.sestu@gmail.com";

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
    };
  };

  programs.ssh.enable = true;
  services.ssh-agent.enable = true;
}
