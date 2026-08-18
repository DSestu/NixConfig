{
  lib,
  options,
  pkgs,
  ...
}: let
  identity = import ../_user-identity.nix;
  # Detect which module schema we're being evaluated against.
  # `programs.fish.{enable,shellAliases,interactiveShellInit}` exist on both
  # NixOS and home-manager — but `programs.fish.{plugins,functions}` and
  # `xdg.configFile` are HM-only. NixOS gets the equivalent by shipping
  # vendor packages into `share/fish/vendor_*.d/` (see below).
  inherit (import ../_schema-detect.nix {inherit options;}) isHM isNixOS;

  # Packages used by the shell (eza/fzf/yazi/micro + a Nerd Font for Tide).
  fishExtraPackages = with pkgs; [
    eza
    yazi
    micro
    fzf
    fd
    bat # powers fzf.fish's file-search preview (_fzf_preview_file)
    mdcat # markdown renderer used by yazi's piper previewer
    nerd-fonts.meslo-lg
    # custom packages
    (import ./fish_config/repo-report.nix {inherit pkgs;})
  ];

  # Official yazi plugin collection, maintained in lockstep with yazi's Lua
  # API (third-party glow.yazi broke on yazi 26). piper.yazi pipes an
  # arbitrary shell command into the previewer; glow does the rendering.
  yaziPluginsRepo = pkgs.fetchFromGitHub {
    owner = "yazi-rs";
    repo = "plugins";
    rev = "0be29a913ad61c6d119abfaaf253e96e6af5db67";
    hash = "sha256-IDmmXzQKFx3QZ9u5lMwcTOeWeMPWzIBeKBXkGAgJMaI=";
  };

  # Single source of truth for which fish plugins we install. Both branches
  # derive from this list: HM via `programs.fish.plugins = fishPluginList`,
  # NixOS via `environment.systemPackages = ... fishPluginPackages`.
  # zoxide's shell function is renamed to `j` so it can coexist with the `z`
  # fish plugin below, which already binds `z`. Consumed by both schema
  # branches (NixOS calls the option `flags`, home-manager calls it `options`).
  zoxideInitFlags = ["--cmd" "j"];

  fishPluginNames = ["tide" "fzf-fish" "z"];
  fishPluginPackages = map (n: pkgs.fishPlugins.${n}) fishPluginNames;
  fishPluginList =
    map (n: {
      name = n;
      src = pkgs.fishPlugins.${n}.src;
    })
    fishPluginNames;

  commonShellAliases = {
    l = "eza -Bhm --icons --no-user --git --time-style long-iso --group-directories-first --color=always --color-scale=age -F --no-permissions -s extension --git-ignore --git --git-repos";
    la = "l -a";
    ll = "l -la";
    lt = "ll -T";
    pc = "git diff --name-only --diff-filter ACMR origin/master...HEAD | xargs pre-commit run --files";
    checks = "post_install_checks";
    # Autoreloading git diff in the diffnav TUI (--watch drives its own
    # command, so no pipe). Extra args pass through, e.g.
    #   dnw --watch-cmd "git diff HEAD" --watch-interval 5s
    dnw = "diffnav --watch";
    # gh-dash TUI dashboard (config in modules/home/dev.nix, programs.gh-dash).
    ghd = "gh dash";
  };

  # Mamba hook — the MAMBA_EXE store path changes each rebuild, so resolve
  # from $PATH rather than hardcoding a /nix/store path.
  commonInteractiveShellInit = ''
    # fzf.fish (ctrl+t file search) previews files with this command; the path
    # is appended and eval'd. bat gives syntax-highlighted, line-numbered output;
    # --line-range caps the preview so huge files stay snappy. (See
    # https://pragmaticpineapple.com/four-useful-fzf-tricks-for-your-terminal/)
    set -g fzf_preview_file_cmd bat --style=numbers --color=always --line-range :500

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
    gmp = ''
      set DEFAULT_BRANCH (git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
      git checkout $DEFAULT_BRANCH && git pull
    '';

    # NOTE: `ns` (and its former `sandbox`/`cowbox` modes + their Tide badges)
    # now live in the shareable module modules/dual/ns/. Not defined here.

    # Wrapper that feeds cachix its auth token from the agenix secret
    # (declared in nixos/modules/secrets.nix, decrypted to tmpfs at boot).
    #
    # Injected per-invocation via `env` rather than exported globally: a
    # `set -gx CACHIX_AUTH_TOKEN` in interactiveShellInit would put a live
    # push credential in the environment of every child process — including
    # `ns` throwaway shells and anything they run. `env` also resolves
    # `cachix` from PATH, so it reaches the real binary and not this
    # function (no recursion).
    #
    # Guarded on readability so this degrades to plain `cachix` where the
    # secret is absent: non-NixOS hosts, and NixOS hosts where
    # cachix-auth-token.age hasn't been created yet. Pull-only use needs no
    # token at all — the substituters in nixos/base.nix cover that.
    cachix = ''
      set -l token_file /run/agenix/cachix-auth-token
      if test -r $token_file
        env CACHIX_AUTH_TOKEN=(cat $token_file) cachix $argv
      else
        command cachix $argv
      end
    '';

    # Matrix-style typewriter greeting (randomized per-char delay), then a
    # one-line cheatsheet for the fuzzy finders:
    #   ctrl-f  browse user-defined functions (browse_functions)
    #   alt-a   browse shell aliases          (browse_aliases)
    #   ctrl-g  attach to a tmux session      (browse_sessions / sesh)
    #   ctrl-r  search command history        (fzf.fish)
    #   ctrl-t  find files                    (fzf.fish _fzf_search_directory)
    #   **<tab> expand recursive-glob suggestions (fish builtin)
    # …and a tmux line. prefix+S is ours (sesh, see modules/home/dev.nix);
    # prefix+s / prefix+d are tmux builtins. Printed only inside tmux, where
    # the bindings actually resolve.
    fish_greeting = ''
      set_color brgreen
      set -l msg "Knock, knock, $USER."
      set -l i 1
      while test $i -le (string length -- $msg)
        printf '%s' (string sub -s $i -l 1 -- $msg)
        sleep (math (random 5 80) / 1000)
        set i (math $i + 1)
      end
      set_color normal
      printf '\n'
      printf "🔍  %sctrl-f%s functions · %salt-a%s aliases · %sctrl-r%s commands · %sctrl-t%s files · %sctrl-g%s sessions · %s**<tab>%s suggestions\n" (set_color blue) (set_color normal) (set_color blue) (set_color normal) (set_color blue) (set_color normal) (set_color blue) (set_color normal) (set_color blue) (set_color normal) (set_color blue) (set_color normal)
      # Throwaway shells (see the `ns` command, modules/dual/ns). Each token is
      # tinted to match its Tide badge: ns=nix-blue, --=green, !=sand, @=violet,
      # -N=red (offline), -h=dim.
      printf "📦  %sns%s <pkg> run · <pkg> %s--%s shell · %s!%s isolated · %s@%s rehearse (reverts) · %s-N%s offline · ns %s-h%s\n" (set_color 7EBAE4) (set_color normal) (set_color 5FD700) (set_color normal) (set_color D7AF5F) (set_color normal) (set_color AF87FF) (set_color normal) (set_color CC0000) (set_color normal) (set_color 6C6C6C) (set_color normal)
      if set -q TMUX
        printf "🪟  %sctrl-b S%s sessions (sesh) · %sctrl-b s%s tree · %sctrl-b d%s detach · %sctrl-b w%s windows\n" (set_color blue) (set_color normal) (set_color blue) (set_color normal) (set_color blue) (set_color normal) (set_color blue) (set_color normal)
      end
    '';

    browse_functions = let
      whitelist = lib.filter (n: n != "browse_functions") (lib.attrNames userFunctions);
    in ''
      # Baked list from userFunctions, plus any names other modules register
      # at runtime via `set -ga __user_browse_functions <name>` (e.g. the
      # `ns` module ships a conf.d snippet that appends `ns`).
      set -l whitelist ${lib.concatStringsSep " " whitelist} $__user_browse_functions
      functions -a | while read -l f
        if contains -- $f $whitelist
          echo $f
        end
      end | fzf --preview 'functions {}'
    '';

    # Fuzzy-browse the shell aliases defined in this config. `alias` lists
    # every alias as `alias NAME 'CMD'`; we keep just the NAME and filter to
    # the names in `commonShellAliases` (fish autoloads its own alias-like
    # functions such as fish_vi_dec/inc, which we don't want here). The fzf
    # preview shows each alias's full expansion — aliases are functions, so
    # `functions NAME` prints the wrapped command. Bound to alt+a in
    # fish_user_key_bindings (mirrors browse_functions on ctrl+f).
    browse_aliases = ''
      set -l whitelist ${lib.concatStringsSep " " (lib.attrNames commonShellAliases)}
      alias | string replace -r "^alias (\\S+) .*" '$1' | while read -l a
        if contains -- $a $whitelist
          echo $a
        end
      end | fzf --preview 'functions {}'
    '';

    # Fuzzy-pick a tmux session and attach to it. The same picker as tmux's
    # prefix+S binding (modules/home/dev.nix), reachable on ctrl+g from a bare
    # shell — that binding needs a prefix key, so it can't help you get *into*
    # tmux in the first place.
    #
    # `sesh connect` attaches from outside tmux and switch-clients from inside,
    # so this is safe to hit in a dmux pane too (no nested server). Guarded on
    # `command -q` because this module is shared with hosts that don't import
    # modules/home/dev.nix and so have no sesh.
    browse_sessions = ''
      if not command -q sesh
        echo "sesh is not installed on this host" >&2
        return 1
      end
      # Live tmux sessions first, then configured ones, then zoxide's frecent
      # directories. sesh treats a missing zoxide as fatal rather than skipping
      # it, so this listing depends on programs.zoxide staying enabled.
      #
      # ctrl-x kills the highlighted session and refreshes the list in place.
      # `{2..}` drops the icon column that --icons prepends. Rows that are
      # zoxide directories rather than live sessions have no session to kill,
      # hence the silenced failure — kill-session just no-ops on them.
      set -l target (sesh list --icons | fzf --no-sort --ansi \
        --border-label ' sesh ' --prompt '⚡  ' \
        --header 'enter: attach · ctrl-x: kill · esc: cancel' \
        --bind 'ctrl-x:execute-silent(tmux kill-session -t {2..} 2>/dev/null)+reload(sesh list --icons)')
      if test -z "$target"
        commandline -f repaint
        return 0
      end
      sesh connect $target
      commandline -f repaint
    '';

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
      bind \cf browse_functions
      bind \ea browse_aliases
      # ctrl+g ("go to session") is unbound in fish's presets.
      bind \cg browse_sessions
      # fzf.fish ships file/dir search on ctrl+alt+f; also expose it on ctrl+t.
      bind \ct _fzf_search_directory
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
          if test "$login_name" = "${identity.tailscaleAccount}"
            echo "PASS tailscale auth: logged in as $login_name"
          else
            echo "WARN tailscale auth: logged in as $login_name (expected ${identity.tailscaleAccount})"
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

      # See the HM branch for why zoxide lands on `j`. The NixOS module spells
      # the init arguments `flags`; home-manager spells them `options`.
      programs.zoxide = {
        enable = true;
        flags = zoxideInitFlags;
      };
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

      # zoxide is installed for sesh's benefit — a bare `sesh list` probes it
      # and treats a missing zoxide as fatal, so without it the session picker
      # comes up empty. It lands on `j`, not `z`, because the `z` fish plugin
      # above already owns that name. The two keep separate frecency databases
      # and will not agree; `j` is the one sesh reads from.
      programs.zoxide = {
        enable = true;
        options = zoxideInitFlags;
      };

      # Yazi config is per-user (~/.config/yazi), so HM-only; root's yazi on
      # NixOS keeps upstream defaults. `settings` merges over yazi's builtin
      # defaults, so only the overridden keys are declared here.
      programs.yazi = {
        enable = true;
        # HM's shell wrapper (cd to yazi's exit directory) replaces the
        # hand-written `y` fish function that used to live in userFunctions.
        shellWrapperName = "y";
        settings = {
          # `edit` is the opener yazi's default open rules dispatch text
          # files to; overriding it makes micro the editor everywhere.
          opener.edit = [
            {
              run = ''micro "$@"'';
              block = true;
            }
          ];
          plugin.prepend_previewers = [
            {
              url = "*.md";
              # $w = preview pane width, substituted by piper. mdcat over
              # glow: glow takes ~2.4ms/line (4.8s for 2k lines) vs mdcat's
              # ~20ms flat; --ansi forces formatting despite piped stdout.
              # piper re-runs this on EVERY scroll tick, so render once into
              # a cache keyed by inode+mtime+width and cat it afterwards.
              run = ''piper -- c="''${TMPDIR:-/tmp}/yazi-mdcat-$(stat -c%i-%Y "$1")-$w"; [ -s "$c" ] || mdcat --columns=$w --ansi "$1" > "$c"; cat "$c"'';
            }
          ];
        };
        plugins.piper = "${yaziPluginsRepo}/piper.yazi";
      };
    })
  ];
}
