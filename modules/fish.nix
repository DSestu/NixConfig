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
    nerd-fonts.meslo-lg
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
    ];

    shellAliases = {
      l = "eza -Bhm --icons --no-user --git --time-style long-iso --group-directories-first --color=always --color-scale=age -F --no-permissions -s extension --git-ignore";
      la = "l -a";
      ll = "l -la";
      lt = "ll -T";
      pc = "git diff --name-only --diff-filter ACMR origin/master...HEAD | xargs pre-commit run --files";
      checks = "post_install_checks";
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

      post_install_checks = ''
        echo "== Post-install checks =="

        # Git identity
        set git_name (git config --global --get user.name 2>/dev/null)
        set git_email (git config --global --get user.email 2>/dev/null)
        if test -n "$git_name"; and test -n "$git_email"
          echo "PASS git identity: $git_name <$git_email>"
        else
          echo "FAIL git identity missing (set programs.git.userName/userEmail)"
        end

        # GitHub auth (HTTPS workflow)
        if type -q gh
          if gh auth status -h github.com >/dev/null 2>&1
            echo "PASS github auth: gh is logged in"
          else
            echo "WARN github auth: run 'gh auth login'"
          end
        else
          echo "WARN github auth: gh CLI not installed"
        end

        # SSH key + agent (SSH workflow)
        echo "Checking for SSH key: running 'test -f \$HOME/.ssh/id_ed25519 -o -f \$HOME/.ssh/id_rsa'"
        if test -f "$HOME/.ssh/id_ed25519" -o -f "$HOME/.ssh/id_rsa"
          echo "PASS ssh key: key file exists"
        else
          echo "WARN ssh key: generate one with 'ssh-keygen -t ed25519 -C \"your_email\"'"
        end


        if ssh-add -l >/dev/null 2>&1
          echo "PASS ssh-agent: at least one key loaded"
        else
          echo "WARN ssh-agent: no loaded keys (try 'ssh-add ~/.ssh/id_ed25519')"
        end

        # Tailscale
        if type -q tailscale
          if systemctl is-enabled --quiet tailscaled 2>/dev/null
            echo "PASS tailscale service: enabled"
          else
            echo "WARN tailscale service: not enabled"
          end

          if systemctl is-active --quiet tailscaled 2>/dev/null
            echo "PASS tailscale daemon: running"
          else
            echo "WARN tailscale daemon: not running"
          end

          set login_name (tailscale status --json 2>/dev/null | string match -r '"LoginName":"[^"]+"' | head -n1 | string replace -r '^"LoginName":"([^"]+)"$' '$1')
          if test -n "$login_name"
            if test "$login_name" = "david.sestu@gmail.com"
              echo "PASS tailscale auth: logged in as $login_name"
            else
              echo "WARN tailscale auth: logged in as $login_name (expected david.sestu@gmail.com)"
            end
          else
            echo "WARN tailscale auth: not logged in (run 'sudo tailscale up')"
          end
        else
          echo "WARN tailscale: CLI not installed"
        end
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
