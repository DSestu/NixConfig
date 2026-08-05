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
  # nixpkgs lags upstream github/gh-stack (0.0.4 vs 0.0.8). Bump src +
  # vendorHash until nixpkgs catches up; overrideAttrs propagates
  # vendorHash to the internal goModules derivation.
  gh-stack = pkgs.gh-stack.overrideAttrs (old: {
    version = "0.0.8";
    src = pkgs.fetchFromGitHub {
      owner = "github";
      repo = "gh-stack";
      tag = "v0.0.8";
      hash = "sha256-N0S/zQ+JsFAKzC780m3lwiZgsCoCjtcWgDB/MJy6jYU=";
    };
    vendorHash = "sha256-CxsHRC5AbApxcsavyaBmoPtTUHy5jlaQ7BLvgE6mJJ4=";
    # v0.0.8 added Go integration tests that shell out to git.
    nativeCheckInputs = (old.nativeCheckInputs or []) ++ [pkgs.git];
  });
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
    ./dev/cursor.nix
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
      diffnav # git diff pager with file tree (wraps delta)
      delta # required backend for diffnav
      quarto
      tableplus
      nodejs
      nixd # Nix language server
    ]
    ++ [warpPkg];

  programs.gh = {
    enable = true;
    extensions = [gh-stack];
    settings = {
      git_protocol = "https";
      aliases.co = "pr checkout";
      aliases.pc = "pr create";
    };
  };

  # gh-dash is installed here (not in programs.gh.extensions above): this
  # module adds pkgs.gh-dash to home.packages AND registers it as a gh
  # extension, and writes ~/.config/gh-dash/config.yml from `settings`.
  programs.gh-dash = {
    enable = true;
    settings = {
      # Use diffnav to view PR/issue diffs (the `d` key) instead of less.
      pager.diff = "diffnav";
      # Fixes "local path to repo not specified": map owner/* -> local clone.
      # All repos are cloned flat under ~/github/<repo>; the value's trailing
      # /* is replaced with the repo name at checkout time.
      repoPaths = {
        "DSestu/*" = "~/github/*";
        "sencrop/*" = "~/github/*";
      };
      # Overriding a builtin REPLACES its default keys (gh-dash calls
      # SetKeys), so binding up/down/nextSection/prevSection to only the
      # arrow keys removes the default k/j/l/h vim bindings.
      keybindings = {
        universal = [
          {
            key = "up";
            builtin = "up";
          } # was up/k -> drop k
          {
            key = "down";
            builtin = "down";
          } # was down/j -> drop j
          {
            key = "right";
            builtin = "nextSection";
          } # was right/l -> drop l
          {
            key = "left";
            builtin = "prevSection";
          } # was left/h -> drop h
          {
            key = "ctrl+down";
            builtin = "pageDown";
          } # preview page down (was ctrl+d)
          {
            key = "ctrl+up";
            builtin = "pageUp";
          } # preview page up (was ctrl+u)
        ];
        # `label` defaults to L in both views; move it to lowercase l
        # (freed up now that l no longer navigates sections).
        prs = [
          {
            key = "l";
            builtin = "label";
          }
        ];
        issues = [
          {
            key = "l";
            builtin = "label";
          }
        ];
      };
    };
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = identity.gitName;
      user.email = identity.gitEmail;
      init.defaultBranch = "main";
      pull.rebase = false;
      core.pager = "diffnav";
    };
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*" = {
      ForwardAgent = false;
      AddKeysToAgent = "no";
      Compression = false;
      ServerAliveInterval = 0;
      ServerAliveCountMax = 3;
      HashKnownHosts = false;
      UserKnownHostsFile = "~/.ssh/known_hosts";
      ControlMaster = "no";
      ControlPath = "~/.ssh/master-%r@%n:%p";
      ControlPersist = "no";
    };
  };
  services.ssh-agent.enable = true;
}
