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
    gh
    tableplus
  ];

  programs.git = {
    enable = true;
    settings = {
      user.name = "DSestu";
      user.email = "david.sestu@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = false;
    };
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks."*" = {
      forwardAgent = false;
      addKeysToAgent = "no";
      compression = false;
      serverAliveInterval = 0;
      serverAliveCountMax = 3;
      hashKnownHosts = false;
      userKnownHostsFile = "~/.ssh/known_hosts";
      controlMaster = "no";
      controlPath = "~/.ssh/master-%r@%n:%p";
      controlPersist = "no";
    };
  };
  services.ssh-agent.enable = true;
}
