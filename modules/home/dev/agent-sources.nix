# Shared upstream pins for AI coding agents.
#
# `dev/claude-code.nix` and `dev/cursor.nix` both import this file so the two
# agents are fed from the *same* pinned commits — one place to bump, no skew
# between what Claude sees and what Cursor sees.
#
# Only Claude Code understands the marketplace/plugin machinery, so it also
# consumes `marketplaces` / `pluginEntries` directly. Cursor has no plugin
# loader, so it gets flat skill/command trees assembled from the same sources.
#
# Update workflow (unchanged):
#   1. bump rev to the desired commit SHA
#   2. set hash to lib.fakeHash, rebuild, copy the hash Nix reports back here
#   3. bump version if the plugin's plugin.json version changed
{
  pkgs,
  lib,
}: let
  # ─── Claude Code plugin marketplaces ────────────────────────────────────
  # `pluginSubpath` is the path within the repo where the plugin lives
  # (matches the `source` field in the marketplace's marketplace.json).
  # `skillsSubpath` / `commandsSubpath` are relative to the plugin root and
  # exist only so Cursor can be handed the same skills and commands.
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
          skillsSubpath = "skills";
          commandsSubpath = ".claude/commands";
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
          skillsSubpath = "skills";
        };
      };
    };
  };

  # ─── Plain skill repos (no marketplace.json / plugin.json) ───────────────
  # Repos that just ship a `skills/` tree of <name>/SKILL.md dirs. The format
  # is identical for Claude Code and Cursor, so both link the same tree.
  skillRepos = {
    refactoring-skills = {
      owner = "mickeyyaya";
      repo = "refactoring-skills";
      rev = "cd0c22762849bd846115a1e10f403759bd7e4f92";
      hash = "sha256-mCMmfULCtiLJ0JTSGSWbC6f0+qFeWwJ0RqrzQbHBX9M=";
      # Subdirectory holding the skill folders.
      skillsSubpath = "skills";
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
      skillsSubpath = p.skillsSubpath or null;
      commandsSubpath = p.commandsSubpath or null;
      src = marketplaceSrcs.${mpName};
      id = "${pluginName}@${mpName}";
    }) (mp.plugins or {}))
  marketplaces);

  # Store path of a plugin's own root (what CLAUDE_PLUGIN_ROOT points at).
  pluginRootOf = e:
    if e.pluginSubpath == ""
    then e.src
    else "${e.src}/${e.pluginSubpath}";

  # id ("claude-mem@thedotmack") -> plugin root store path. Lets consumers
  # reach into a plugin for things Cursor needs wired by hand, e.g. an MCP
  # server entrypoint.
  pluginRoots =
    lib.listToAttrs (map (e: lib.nameValuePair e.id (pluginRootOf e)) pluginEntries);

  # Subdirectories of plugins that hold skills / commands, skipping plugins
  # that ship neither.
  pluginDirs = attr:
    lib.concatMap (e:
      lib.optional (e.${attr} != null) "${pluginRootOf e}/${e.${attr}}")
    pluginEntries;

  skillRepoDirs = lib.mapAttrsToList (_: r:
    if r.skillsSubpath == ""
    then mkSrc r
    else "${mkSrc r}/${r.skillsSubpath}")
  skillRepos;

  joinTree = name: paths: pkgs.symlinkJoin {inherit name paths;};
in {
  inherit marketplaces skillRepos marketplaceSrcs pluginEntries pluginRoots;

  # Claude Code loads plugin skills through the plugin loader (namespaced as
  # `plugin:skill`), so only the plain skill repos go in ~/.claude/skills.
  claudeSkillsTree = joinTree "claude-skills" skillRepoDirs;

  # Cursor has no plugin loader: flatten repo skills *and* plugin skills into
  # one tree so ~/.cursor/skills ends up with the same skill set.
  cursorSkillsTree =
    joinTree "cursor-skills" (skillRepoDirs ++ pluginDirs "skillsSubpath");

  # Plugin slash-commands, for ~/.cursor/commands.
  cursorCommandsTree = joinTree "cursor-commands" (pluginDirs "commandsSubpath");
}
