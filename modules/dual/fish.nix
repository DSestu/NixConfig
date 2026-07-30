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
    nerd-fonts.meslo-lg
    # custom packages
    (import ./fish_config/repo-report.nix {inherit pkgs;})
  ];

  # Single source of truth for which fish plugins we install. Both branches
  # derive from this list: HM via `programs.fish.plugins = fishPluginList`,
  # NixOS via `environment.systemPackages = ... fishPluginPackages`.
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

    # `nix shell` shortcut that runs a command from a package instead of
    # dropping you into a subshell. Uses the new `nix shell` CLI (not
    # `nix-shell`): --command runs in your current fish shell, so Ctrl+C
    # reaches the program directly and no bash wrapper gets in the way. The
    # first arg is both the package name and the command to run; remaining
    # args are forwarded to it. The package resolves via the `nixpkgs` flake
    # registry entry (unstable by default).
    #   ns grep -ri foo .   → nix shell nixpkgs#grep --command grep -ri foo .
    # Append a bare `--` to skip execution and get an interactive shell (your
    # $SHELL, i.e. fish) instead. In this mode EVERY arg before `--` is a
    # package to add to the shell (not command arguments):
    #   ns grep --                → nix shell nixpkgs#grep          (interactive)
    #   ns grep ripgrep fd --     → nix shell nixpkgs#grep nixpkgs#ripgrep nixpkgs#fd
    ns = ''
      if test (count $argv) -eq 0
        echo "usage: ns <package> [args...]   run <package> via nix shell" >&2
        echo "       ns <package>... --        spawn an interactive shell with those packages" >&2
        return 1
      end

      if test $argv[-1] = "--"
        # Shell mode: every arg before the trailing `--` is a package on PATH.
        set -l pkgs $argv[1..-2]
        if test (count $pkgs) -eq 0
          echo "usage: ns <package>... --   spawn an interactive shell with those packages" >&2
          return 1
        end
        # The new `nix shell` sets no marker env var (unlike old nix-shell's
        # IN_NIX_SHELL), so Tide's nix_shell prompt item stays dark. Inject
        # IN_NIX_SHELL ourselves — set to the package list — so the spawned
        # fish shows a themed badge naming what's on PATH. `set -l badge …`
        # keeps it one space-joined token (fish would otherwise splat the list
        # into separate `env` args). fish expands nixpkgs#$pkgs element-wise.
        #
        # NS_SHELL marks this as an ns shell so tide-theme.fish paints the
        # nix_shell badge coral (vs blue for a genuine nix-shell). It must be
        # exported, not a fish var: Tide renders its prompt in a background
        # `fish -c` child that re-sources config, and only inherited env vars
        # (like IN_NIX_SHELL) cross into it — a `set -g` in this shell would not.
        set -l badge (string join ' ' $pkgs)
        env IN_NIX_SHELL=$badge NS_SHELL=1 nix shell nixpkgs#$pkgs
      else
        # Standard mode: first arg is both package and command; the rest are
        # its args. --command takes them as separate tokens, so no escaping.
        set -l pkg $argv[1]
        set -l rest $argv[2..-1]
        nix shell nixpkgs#$pkg --command $pkg $rest
      end
    '';

    # Throwaway sandboxed shell for poking at untrusted repos. Backed by
    # bubblewrap (`bwrap`, in home.packages), the same unprivileged
    # user-namespace sandbox Nix uses for build isolation — no root, no
    # daemon. A fresh temp dir is bind-mounted read-write at /work and is the
    # ONLY writable path outside /tmp; everything else the shell can see is
    # read-only. The whole temp dir is `rm -rf`'d when you exit the shell, so
    # any clone, `npm install`, `pip install`, build artifact, etc. vanishes.
    #
    #   sandbox                     empty /work, network ON, drop into fish
    #   sandbox <git-url>           clone the repo into /work/repo and cd there
    #   sandbox --no-net [<git-url>] same, but no network inside the sandbox
    #
    # Network defaults ON because the point is usually to run installs that
    # fetch (npm/pip/cargo). Pass --no-net to cut the sandbox off from the
    # network entirely (the clone still happens first, on the host, so it
    # works regardless). Read-only host paths are bind-mounted with
    # `--ro-bind-try` so the same function works on FHS hosts (Kali: real
    # /usr,/bin,/lib) and on NixOS (where those are absent and everything
    # lives under /nix); /nix is always bound since the fish binary lives
    # there. HOME is repointed at /work (writable, ephemeral) so history and
    # any config writes stay inside the throwaway dir.
    #
    # The sandbox gets your Tide theme, functions, and aliases via a WRITABLE
    # throwaway COPY of ~/.config/fish placed in /work (see below). We copy
    # rather than read-only bind because fish writes its universal-variable
    # file (fish_variables) into its own config dir on startup — a read-only
    # mount makes fish spam "Read-only file system" errors on every write.
    # Your real config is never mounted, so untrusted code still can't touch
    # it; the copy is trashed with everything else on exit.
    sandbox = ''
      argparse 'no-net' -- $argv
      or return 1

      if not type -q bwrap
        echo "sandbox: bwrap not found — is bubblewrap installed?" >&2
        return 1
      end

      set -l work (mktemp -d)
      set -l chdir /work

      # Materialise a writable copy of the fish config so the sandbox looks
      # like a normal shell (theme/functions/aliases) yet fish can still write
      # its fish_variables/history. `-L` dereferences the home-manager symlinks
      # into plain files; any store binaries they call stay reachable via the
      # read-only /nix bind. The real config is left untouched on the host.
      if test -d $HOME/.config/fish
        mkdir -p $work/.config
        cp -rL $HOME/.config/fish $work/.config/fish
        # Files copied out of /nix/store are mode 444; make the copy writable
        # so fish can create fish_variables and update its config in-session.
        chmod -R u+w $work/.config/fish
      end

      if set -q argv[1]
        echo "sandbox: cloning $argv[1] into an ephemeral checkout…" >&2
        if not git clone --depth 1 $argv[1] $work/repo
          rm -rf $work
          return 1
        end
        set chdir /work/repo
      end

      set -l netflag --unshare-net
      if set -q _flag_no_net
        echo "sandbox: network DISABLED inside the shell." >&2
      else
        set netflag --share-net
      end

      echo "sandbox: writable /work only; exit the shell to destroy everything." >&2
      bwrap \
        --ro-bind /nix /nix \
        --ro-bind-try /usr /usr \
        --ro-bind-try /bin /bin \
        --ro-bind-try /lib /lib \
        --ro-bind-try /lib64 /lib64 \
        --ro-bind-try /etc /etc \
        --ro-bind-try /run /run \
        --proc /proc \
        --dev /dev \
        --tmpfs /tmp \
        --bind $work /work \
        --chdir $chdir \
        --setenv HOME /work \
        --setenv SANDBOX 1 \
        --unshare-all $netflag \
        --die-with-parent \
        fish

      rm -rf $work
    '';

    # Matrix-style typewriter greeting (randomized per-char delay), then a
    # one-line cheatsheet for the fuzzy finders:
    #   ctrl-f  browse user-defined functions (browse_functions)
    #   alt-a   browse shell aliases          (browse_aliases)
    #   ctrl-r  search command history        (fzf.fish)
    #   ctrl-t  find files                    (fzf.fish _fzf_search_directory)
    #   **<tab> expand recursive-glob suggestions (fish builtin)
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
      printf "🔍  %sctrl-f%s functions · %salt-a%s aliases · %sctrl-r%s commands · %sctrl-t%s files · %s**<tab>%s suggestions\n" (set_color blue) (set_color normal) (set_color blue) (set_color normal) (set_color blue) (set_color normal) (set_color blue) (set_color normal) (set_color blue) (set_color normal)
    '';

    browse_functions = let
      whitelist = lib.filter (n: n != "browse_functions") (lib.attrNames userFunctions);
    in ''
      set -l whitelist ${lib.concatStringsSep " " whitelist}
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
      # fzf.fish ships file/dir search on ctrl+alt+f; also expose it on ctrl+t.
      bind \ct _fzf_search_directory
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
