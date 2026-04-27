{
  lib,
  options,
  pkgs,
  ...
}: let
  # Detect which module schema we're being evaluated against.
  # `programs.fish.{enable,shellAliases,interactiveShellInit}` exist on both
  # NixOS and home-manager — but `programs.fish.{plugins,functions}` and
  # `xdg.configFile` are HM-only. NixOS gets the equivalent by shipping
  # vendor packages into `share/fish/vendor_*.d/` (see below).
  isHM = options ? home;
  isNixOS = options ? environment && options.environment ? systemPackages;

  # Packages used by the shell (eza/fzf/yazi/micro + a Nerd Font for Tide).
  fishExtraPackages = with pkgs; [
    eza
    yazi
    micro
    fzf
    nerd-fonts.meslo-lg
  ];

  # Single source of truth for which fish plugins we install. Both branches
  # derive from this list: HM via `programs.fish.plugins = fishPluginList`,
  # NixOS via `environment.systemPackages = ... fishPluginPackages`.
  fishPluginNames = ["tide" "fzf-fish" "z"];
  fishPluginPackages = map (n: pkgs.fishPlugins.${n}) fishPluginNames;
  fishPluginList = map (n: {
    name = n;
    src = pkgs.fishPlugins.${n}.src;
  }) fishPluginNames;

  commonShellAliases = {
    l = "eza -Bhm --icons --no-user --git --time-style long-iso --group-directories-first --color=always --color-scale=age -F --no-permissions -s extension --git-ignore";
    la = "l -a";
    ll = "l -la";
    lt = "ll -T";
    pc = "git diff --name-only --diff-filter ACMR origin/master...HEAD | xargs pre-commit run --files";
    checks = "post_install_checks";
  };

  # Mamba hook — the MAMBA_EXE store path changes each rebuild, so resolve
  # from $PATH rather than hardcoding a /nix/store path.
  commonInteractiveShellInit = ''
    if type -q micromamba
      set -gx MAMBA_EXE (command -v micromamba)
      set -gx MAMBA_ROOT_PREFIX "$HOME/github/airflow-dags/micromamba"
      $MAMBA_EXE shell hook --shell fish --root-prefix $MAMBA_ROOT_PREFIX | source
    end
  '';

  # User functions, keyed by function name → body. Consumed directly by HM
  # (`programs.fish.functions`); on NixOS each body is wrapped in
  # `function NAME ... end` and shipped as a `share/fish/vendor_functions.d/`
  # entry by `userFunctionsSystemPkg` below.
  userFunctions = {
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

      # Private repo + remote deployment readiness
      if type -q nixos-anywhere
        echo "PASS deployment tool: nixos-anywhere installed"
      else
        echo "WARN deployment tool: nixos-anywhere missing"
      end

      if type -q git
        set origin_url (git config --get remote.origin.url 2>/dev/null)
        if test -n "$origin_url"
          if string match -qr 'github\\.com[:/]' -- "$origin_url"
            if string match -qr '^git@github\\.com:' -- "$origin_url"
              echo "PASS private repo access: origin uses SSH ($origin_url)"
            else if string match -qr '^https://github\\.com/' -- "$origin_url"
              echo "WARN private repo access: origin uses HTTPS ($origin_url) - ensure 'gh auth login' works on this machine"
            else
              echo "WARN private repo access: unrecognized GitHub remote format ($origin_url)"
            end
          else
            echo "WARN private repo access: origin is not GitHub ($origin_url)"
          end
        else
          echo "WARN private repo access: no git origin remote configured"
        end
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

  # NixOS-only: ship the Tide theme as a vendor_conf.d entry so fish
  # auto-loads it on every shell start. The `00-` prefix sorts before
  # tide's own `tide.fish`, ensuring `tide_*` globals are set before
  # tide's init code runs `set -q tide_left_prompt_items` (otherwise
  # tide treats it as a fresh install and skips its theme-bake step).
  tideThemeSystemPkg = pkgs.writeTextFile {
    name = "fish-tide-theme-system";
    destination = "/share/fish/vendor_conf.d/00-tide-theme.fish";
    text = builtins.readFile ./fish_config/tide-theme.fish;
  };

  # NixOS-only: ship each user function as its own vendor_functions.d/<name>.fish
  # entry. fish autoloads functions on first reference from any directory in
  # `$fish_function_path`, which always includes profile vendor_functions.d/.
  userFunctionsSystemPkg = pkgs.symlinkJoin {
    name = "fish-user-functions-system";
    paths =
      lib.mapAttrsToList (
        name: body:
          pkgs.writeTextFile {
            name = "fish-fn-${name}";
            destination = "/share/fish/vendor_functions.d/${name}.fish";
            text = ''
              function ${name}
              ${body}
              end
            '';
          }
      )
      userFunctions;
  };
in {
  config = lib.mkMerge [
    # Shared on both schemas: enable fish + simple aliases / shell init.
    # NixOS bakes these into the generated `/etc/fish/config.fish`, which
    # fish DOES read (via the `useOperatingSystemEtc` appendix shipped in
    # the nixpkgs fish derivation). HM applies them per-user.
    {
      programs.fish = {
        enable = true;
        shellAliases = commonShellAliases;
        interactiveShellInit = commonInteractiveShellInit;
      };
    }

    # NixOS branch: everything user-facing ships as system packages so it
    # lands under `/run/current-system/sw/share/fish/vendor_*.d/` — the
    # only system-wide path fish actually auto-scans on Nix-built fish
    # (see nixpkgs issue #484885 for why `/etc/fish/{conf.d,functions}/`
    # don't work).
    (lib.optionalAttrs isNixOS {
      environment.systemPackages =
        fishExtraPackages
        ++ fishPluginPackages
        ++ [tideThemeSystemPkg userFunctionsSystemPkg];
    })

    # home-manager branch: native option-based config writes everything
    # to `~/.config/fish/{conf.d,functions}/`, which fish always scans.
    (lib.optionalAttrs isHM {
      home.packages = fishExtraPackages;

      # Same `00-` prefix reasoning as the NixOS branch: load before tide.
      xdg.configFile."fish/conf.d/00-tide-theme.fish".source = ./fish_config/tide-theme.fish;

      programs.fish = {
        plugins = fishPluginList;
        functions = userFunctions;
      };
    })
  ];
}
