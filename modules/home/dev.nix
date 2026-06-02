{
  config,
  pkgs,
  lib,
  nixgl ? null,
  ...
}: let
  identity = import ../_user-identity.nix;
  # On non-NixOS hosts the system's GL/Vulkan drivers can't be loaded by
  # Nix-built binaries (ABI mismatch with libglvnd in the Nix store).
  # nixGL bridges that. NixOS profiles use the system graphics stack
  # directly and skip the wrapper.
  needsNixGL = config.targets.genericLinux.enable && nixgl != null;
  warpPkg =
    if needsNixGL
    then
      pkgs.warp-terminal.overrideAttrs (old: {
        postFixup =
          (old.postFixup or "")
          + ''
            mv $out/bin/warp-terminal $out/bin/.warp-terminal-real
            cat > $out/bin/warp-terminal <<EOF
            #!${pkgs.runtimeShell}
            exec ${nixgl.packages.${pkgs.system}.nixGLIntel}/bin/nixGLIntel $out/bin/.warp-terminal-real "\$@"
            EOF
            chmod +x $out/bin/warp-terminal
          '';
      })
    else pkgs.warp-terminal;
in {
  imports = [
    ./dev/claude-code.nix
  ];

  home.packages = with pkgs;
    [
      devenv
      direnv
      vscode
      code-cursor
      uv
      pixi
      tig # git show | tig
      gh
      quarto
      tableplus
      nodejs
    ]
    ++ [warpPkg];

  programs.git = {
    enable = true;
    settings = {
      user.name = identity.gitName;
      user.email = identity.gitEmail;
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
