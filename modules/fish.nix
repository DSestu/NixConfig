{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    eza
    yazi
    micro
    fzf
  ];

  xdg.configFile."fish/conf.d/tide-theme.fish".source = ./tide-theme.fish;

  programs.fish = {
    enable = true;

    plugins = [
      {
        name = "tide";
        src = pkgs.fishPlugins.tide.src;
      }
      {
        name = "fzf-fish";
        src = pkgs.fishPlugins.fzf-fish.src;
      }
      {
        name = "z";
        src = pkgs.fishPlugins.z.src;
      }
      # {
      #   name = "fish-abbreviation-tips";
      #   src = pkgs.fetchFromGitHub {
      #     owner = "gazorby";
      #     repo = "fish-abbreviation-tips";
      #     rev = "8ef581f61f5d2cac936d6ee2e2f09cfcb48d3755";
      #     hash = "";
      #   };
      # }
    ];

    shellAliases = {
      l = "eza -Bhm --icons --no-user --git --time-style long-iso --group-directories-first --color=always --color-scale=age -F --no-permissions -s extension --git-ignore";
      la = "l -a";
      ll = "l -la";
      lt = "ll -T";
      pc = "git diff --name-only --diff-filter ACMR origin/master...HEAD | xargs pre-commit run --files";
    };

    functions = {
      bind_bang = ''
        switch (commandline -t)[-1]
          case "!"
            commandline -t -- $history[1]
            commandline -f repaint
          case "*"
            commandline -i !
        end
      '';

      bind_dollar = ''
        switch (commandline -t)[-1]
          case "!"
            commandline -f backward-delete-char history-token-search-backward
          case "*"
            commandline -i '$'
        end
      '';

      fish_user_key_bindings = ''
        bind ! bind_bang
        bind '$' bind_dollar
        bind \cH backward-kill-word
      '';

      y = ''
        set tmp (mktemp -t "yazi-cwd.XXXXXX")
        command yazi $argv --cwd-file="$tmp"
        if read -z cwd < "$tmp"; and [ "$cwd" != "$PWD" ]; and test -d "$cwd"
          builtin cd -- "$cwd"
        end
        rm -f -- "$tmp"
      '';
    };

    # Mamba hook — the MAMBA_EXE store path changes each rebuild, so resolve
    # from $PATH rather than hardcoding a /nix/store path.
    interactiveShellInit = ''
      if type -q micromamba
        set -gx MAMBA_EXE (command -v micromamba)
        set -gx MAMBA_ROOT_PREFIX "$HOME/github/airflow-dags/micromamba"
        $MAMBA_EXE shell hook --shell fish --root-prefix $MAMBA_ROOT_PREFIX | source
      end
    '';
  };
}
