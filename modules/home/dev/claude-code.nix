{
  config,
  pkgs,
  lib,
  ...
}: let
  # ─── Declarative plugin pinning ─────────────────────────────────────────
  # Each entry pins a marketplace repo by commit SHA + nar hash. The
  # `pluginSubpath` is the path within that repo where the plugin lives
  # (matches the `source` field in the marketplace's marketplace.json).
  #
  # Update workflow:
  #   1. bump rev to the desired commit SHA
  #   2. set hash to lib.fakeHash, run `nixos-rebuild switch`, copy the
  #      hash Nix reports back here
  #   3. bump version if the plugin's plugin.json version changed
  marketplaces = {
    claude-plugins-official = {
      owner = "anthropics";
      repo = "claude-plugins-official";
      rev = "00679aef889efe36bb0389f81d70b6229a2013ee";
      hash = "sha256-zB1pUtTloc2yTX735voGVkxqU7IyNBjqGJzpFOy9pH0=";
      plugins = {
        pyright-lsp = {
          version = "1.0.0";
          pluginSubpath = "plugins/pyright-lsp";
        };
      };
    };
    claude-code-warp = {
      owner = "warpdotdev";
      repo = "claude-code-warp";
      rev = "b8ad3cc6c1e40b2d2a944f900a4ae0904a54dd7f";
      hash = "sha256-ceNIw6p+T9nyimnRYRX0hUsQjwtou2RkXUquHM+9IcM=";
      plugins = {
        warp = {
          version = "2.0.0";
          pluginSubpath = "plugins/warp";
        };
      };
    };
    addy-agent-skills = {
      owner = "addyosmani";
      repo = "agent-skills";
      rev = "f504276d8e074912f4763e6163b436a4ffc74d0d";
      hash = "sha256-ngGjnKOHDXhQfY9mOhpzSGE8WJPKIApXilOZvae/1qI=";
      plugins = {
        agent-skills = {
          version = "1.0.0";
          # Plugin source is the repo root.
          pluginSubpath = "";
        };
      };
    };
    thedotmack = {
      owner = "thedotmack";
      repo = "claude-mem";
      rev = "0a43ab7632ebedcd3c94cbb79a73df13ec41e9b0";
      hash = "sha256-FZQ8dIL17cqU8heTDh5zVCu+PKXeU4SOaoGFmV5yLvk=";
      plugins = {
        claude-mem = {
          version = "12.7.5";
          pluginSubpath = "plugin";
        };
      };
    };
  };

  # ─── Derived state ──────────────────────────────────────────────────────
  mkSrc = m:
    pkgs.fetchFromGitHub {
      inherit (m) owner repo rev hash;
    };

  marketplaceSrcs = lib.mapAttrs (_: mkSrc) marketplaces;

  pluginEntries = lib.concatLists (lib.mapAttrsToList (mpName: mp:
    lib.mapAttrsToList (pluginName: p: {
      inherit mpName pluginName;
      inherit (p) version pluginSubpath;
      src = marketplaceSrcs.${mpName};
      id = "${pluginName}@${mpName}";
    }) (mp.plugins or {}))
  marketplaces);

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

  settings = {
    inherit enabledPlugins;
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

  toJSON = data: builtins.toJSON data;
in {
  home.packages = [pkgs.claude-code];

  # Read-only symlinks into the nix store — pinned source of truth.
  # Includes user-level CLAUDE.md + rules/ checked into this repo.
  home.file = marketplaceLinks // pluginCacheLinks // {
    ".claude/CLAUDE.md".source = ./claude-files/CLAUDE.md;
    ".claude/rules".source = ./claude-files/rules;
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
  '';
}
