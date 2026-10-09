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
      rev = "b860d6f2554f145fe1e7ac4cdcabca0120d14030";
      hash = "sha256-SwDRZwwQV/NlVvfdaZZn8Y2Ix2rSHw8yggVLLO1+eLw=";
      plugins = {
        pyright-lsp = {
          version = "1.0.0";
          pluginSubpath = "plugins/pyright-lsp";
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
    humanizer = {
      owner = "blader";
      repo = "humanizer";
      rev = "225a6f39ac85f76ee48dbad772ea4abe4ed6c9d8";
      hash = "sha256-n8cbTzhlGf8VnWpPukq7XD2mucIrqyE1XMpAAc5oA8A=";
      plugins = {
        humanizer = {
          version = "2.11.2";
          # Plugin source is the repo root.
          pluginSubpath = "";
          # Unusual layout: SKILL.md sits at the repo root (plugin.json says
          # `skills: ["./"]`), so there is no directory *of* skills to hand
          # Cursor. `skillRootName` wraps the root as a single skill dir.
          skillRootName = "humanizer";
        };
      };
    };
    ponytail = {
      owner = "DietrichGebert";
      repo = "ponytail";
      rev = "9cc65d03aa2da1db7121b912d03596409ee340b8";
      hash = "sha256-diYM3gqcEboVi7OQff/SvlE0TKAIPTJDIggX7rZWslY=";
      plugins = {
        ponytail = {
          version = "4.9.0";
          pluginSubpath = "";
          skillsSubpath = "skills";
          # No commandsSubpath: the repo's commands/ holds Codex-flavoured
          # .toml files, which neither Claude Code nor Cursor loads (both
          # want .md). The six skills carry the same behaviour.
        };
      };
    };
    diagram-design = {
      owner = "cathrynlavery";
      repo = "diagram-design";
      rev = "f4547ee95f88e5b28a52517feff6b6c11cc657f9";
      hash = "sha256-L+2YqVybYQ892nLkaHSRKI4pjFcb506jhDz4U8ju6P8=";
      plugins = {
        diagram-design = {
          version = "2.6.18";
          pluginSubpath = "";
          skillsSubpath = "skills";
          commandsSubpath = "commands";
        };
      };
    };
    context-mode = {
      owner = "mksglu";
      repo = "context-mode";
      rev = "d573d8e1a0db87da3d72bbd7b5cdc88569f4c734";
      hash = "sha256-oEfPBi5qjhDCvz3ZQ/WVNJMkbZ8jouOZrcS1szJ9E+s=";
      plugins = {
        context-mode = {
          version = "1.0.169";
          pluginSubpath = "";
          skillsSubpath = "skills";
        };
      };
    };
    thedotmack = {
      owner = "thedotmack";
      repo = "claude-mem";
      rev = "fa8ab09f06aa05f958c5225cf3756ce52a3ebb96";
      hash = "sha256-orbHBCbEVKbex+tCR+DCg9kz4aqmGyt3PqQcQ0qtOK4=";
      plugins = {
        claude-mem = {
          version = "13.35.0";
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
    i-have-adhd = {
      owner = "ayghri";
      repo = "i-have-adhd";
      rev = "723af7d9afaf43eb871dbcce6129e2bf80de90d5";
      hash = "sha256-5EYLKtrg0RQN0CHR51Sc2qSkgYklu6lqzuH87Dp3gv4=";
      skillsSubpath = "skills";
    };
  };

  # ─── Derived state ──────────────────────────────────────────────────────
  mkSrc = m:
    pkgs.fetchFromGitHub {
      inherit (m) owner repo rev hash;
    };

  marketplaceSrcs = lib.mapAttrs (_: mkSrc) marketplaces;

  # Repo roots of the plain skill repos, for consumers that need a file the
  # skills tree doesn't carry (e.g. i-have-adhd's SessionStart hook script).
  skillRepoSrcs = lib.mapAttrs (_: mkSrc) skillRepos;

  pluginEntries = lib.concatLists (lib.mapAttrsToList (mpName: mp:
    lib.mapAttrsToList (pluginName: p: {
      inherit mpName pluginName;
      inherit (p) version pluginSubpath;
      skillsSubpath = p.skillsSubpath or null;
      commandsSubpath = p.commandsSubpath or null;
      skillRootName = p.skillRootName or null;
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

  # A plugin whose SKILL.md *is* its own root is not a directory of skills, so
  # it cannot be symlinkJoin'd into the flat tree directly (that would splat
  # README.md, agents/, … into ~/.cursor/skills). Link it under its name.
  wrapSkillDir = name: path:
    pkgs.runCommand "skill-dir-${name}" {} ''
      mkdir -p $out
      ln -s ${path} $out/${name}
    '';

  pluginRootSkillDirs =
    lib.concatMap (e:
      lib.optional (e.skillRootName != null)
      (wrapSkillDir e.skillRootName (pluginRootOf e)))
    pluginEntries;

  skillRepoDirs = lib.mapAttrsToList (name: r:
    if r.skillsSubpath == ""
    then skillRepoSrcs.${name}
    else "${skillRepoSrcs.${name}}/${r.skillsSubpath}")
  skillRepos;

  joinTree = name: paths: pkgs.symlinkJoin {inherit name paths;};
in {
  inherit marketplaces skillRepos marketplaceSrcs skillRepoSrcs pluginEntries pluginRoots;

  # Claude Code loads plugin skills through the plugin loader (namespaced as
  # `plugin:skill`), so only the plain skill repos go in ~/.claude/skills.
  claudeSkillsTree = joinTree "claude-skills" skillRepoDirs;

  # Cursor has no plugin loader: flatten repo skills *and* plugin skills into
  # one tree so ~/.cursor/skills ends up with the same skill set.
  cursorSkillsTree =
    joinTree "cursor-skills"
    (skillRepoDirs ++ pluginDirs "skillsSubpath" ++ pluginRootSkillDirs);

  # Plugin slash-commands, for ~/.cursor/commands.
  cursorCommandsTree = joinTree "cursor-commands" (pluginDirs "commandsSubpath");
}
