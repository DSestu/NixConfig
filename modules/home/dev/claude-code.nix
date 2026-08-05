{
  config,
  pkgs,
  lib,
  ...
}: let
  # Upstream pins (marketplaces, plugins, skill repos) live in
  # ./agent-sources.nix so Cursor can be fed from the same commits.
  # See that file for the bump workflow.
  sources = import ./agent-sources.nix {inherit pkgs lib;};
  inherit (sources) marketplaces marketplaceSrcs pluginEntries;

  # ─── JSON payloads claude-code expects ──────────────────────────────────
  enabledPlugins =
    lib.listToAttrs (map (e: lib.nameValuePair e.id true) pluginEntries);

  knownMarketplaces =
    lib.mapAttrs (mpName: _: {
      source = {
        source = "github";
        repo = "${marketplaces.${mpName}.owner}/${marketplaces.${mpName}.repo}";
      };
      installLocation = "${config.home.homeDirectory}/.claude/plugins/marketplaces/${mpName}";
      lastUpdated = "1970-01-01T00:00:00.000Z";
    })
    marketplaces;

  installedPlugins = {
    version = 2;
    plugins = lib.listToAttrs (map (e:
      lib.nameValuePair e.id [
        {
          scope = "user";
          installPath = "${config.home.homeDirectory}/.claude/plugins/cache/${e.mpName}/${e.pluginName}/${e.version}";
          version = e.version;
          installedAt = "1970-01-01T00:00:00.000Z";
          lastUpdated = "1970-01-01T00:00:00.000Z";
          gitCommitSha = marketplaces.${e.mpName}.rev;
        }
      ])
    pluginEntries);
  };

  # i-have-adhd ships its ruleset as an opt-in-always skill: a SessionStart
  # hook that prints SKILL.md's body whenever the flag file exists. It's
  # normally installed as a plugin (hooks.json), but we link it as a plain
  # skill repo, so the hook is declared here instead. The script resolves
  # SKILL.md relative to its own path, so pointing at the store copy works.
  adhdAlwaysOnHook = "${sources.skillRepoSrcs.i-have-adhd}/hooks/always-on.sh";

  settings = {
    inherit enabledPlugins;
    hooks.SessionStart = [
      {
        matcher = "startup|resume|clear|compact";
        hooks = [
          {
            type = "command";
            command = "sh ${adhdAlwaysOnHook}";
            timeout = 5;
            statusMessage = "Loading i-have-adhd ruleset...";
          }
        ];
      }
    ];
    extraKnownMarketplaces =
      lib.mapAttrs (mpName: _: {
        source = {
          source = "github";
          repo = "${marketplaces.${mpName}.owner}/${marketplaces.${mpName}.repo}";
        };
      })
      marketplaces;
    effortLevel = "medium";
    model = "opus[1m]";
    includeCoAuthoredBy = false;
  };

  # ─── home.file entries: marketplace + per-plugin cache symlinks ─────────
  marketplaceLinks = lib.mapAttrs' (mpName: src:
    lib.nameValuePair ".claude/plugins/marketplaces/${mpName}" {
      source = src;
    })
  marketplaceSrcs;

  pluginCacheLinks = lib.listToAttrs (map (e:
    lib.nameValuePair ".claude/plugins/cache/${e.mpName}/${e.pluginName}/${e.version}" {
      source =
        if e.pluginSubpath == ""
        then e.src
        else "${e.src}/${e.pluginSubpath}";
    })
  pluginEntries);

  toJSON = builtins.toJSON;
in {
  home.packages = [pkgs.claude-code];

  # Read-only symlinks into the nix store — pinned source of truth.
  # Includes user-level CLAUDE.md + rules/ checked into this repo.
  home.file = marketplaceLinks // pluginCacheLinks // {
    ".claude/CLAUDE.md".source = ./claude-files/CLAUDE.md;
    ".claude/rules".source = ./claude-files/rules;
    # `recursive` links each skill individually so hand-written skills can
    # live in ~/.claude/skills alongside the pinned ones.
    ".claude/skills" = {
      source = sources.claudeSkillsTree;
      recursive = true;
    };
  };

  # Index + settings JSON files are written as regular (mutable) files so
  # claude-code can update lastUpdated timestamps without crashing. Each
  # home-manager activation overwrites them, re-asserting the pin.
  home.activation.claudeCodePluginIndex = lib.hm.dag.entryAfter ["writeBoundary"] ''
    install -d -m 0700 "$HOME/.claude/plugins"
    install -m 0600 /dev/stdin "$HOME/.claude/plugins/known_marketplaces.json" <<'JSON'
    ${toJSON knownMarketplaces}
    JSON
    install -m 0600 /dev/stdin "$HOME/.claude/plugins/installed_plugins.json" <<'JSON'
    ${toJSON installedPlugins}
    JSON
    install -d -m 0700 "$HOME/.claude"
    install -m 0600 /dev/stdin "$HOME/.claude/settings.json" <<'JSON'
    ${toJSON settings}
    JSON
    # Opt-in flag the i-have-adhd SessionStart hook checks: present = always on.
    touch "$HOME/.claude/.i-have-adhd-always"
  '';
}
