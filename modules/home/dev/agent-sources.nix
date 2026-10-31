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
      rev = "58267944f92187b7d6a1c822165c96c81c864806";
      hash = "sha256-f6wBcSVGNvY+lqFbs0cczTRfRjYZrqWb0hslE7IX2p8=";
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
      rev = "8bfcc1f9916f2eea55494d8c1fa7f4bde867dd9e";
      hash = "sha256-PlvPPYcFT+kNrkxWxrakNfwD38KuAT+vDnwodwUwXOw=";
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
      rev = "8c307f367c91bd974002f10f2be2965d642c13df";
      hash = "sha256-PkMQTzYs/0uUa6/liyndLCblx30N96XYlVQYc0c8Hfo=";
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
      rev = "09c434ab73ca43761c5d8b0c5d341926c2fba710";
      hash = "sha256-sVnxA4rfxa2SlS2g+2+q3odRq0VJz1z7PEVHW2QRPQI=";
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
      rev = "0b9b10cab3dbf695642fa1a6c4b4f60df9083689";
      hash = "sha256-Kt1kWXvWSRi/rA628LS3YtCpFEysR/LKmK6urpVlxOg=";
      plugins = {
        diagram-design = {
          version = "2.6.18";
          pluginSubpath = "";
          skillsSubpath = "skills";
          commandsSubpath = "commands";
        };
      };
    };
    impeccable = {
      owner = "pbakaus";
      repo = "impeccable";
      rev = "3671d50f0ac9a662ce0615e85a256110c9cd720b";
      hash = "sha256-RxnMce1gTb0erGw+j6+T5i8orcgbOTci3/KnehBYTPY=";
      plugins = {
        impeccable = {
          version = "4.7.1";
          pluginSubpath = "plugin";
          skillsSubpath = "skills";
        };
      };
    };
    context-mode = {
      owner = "mksglu";
      repo = "context-mode";
      rev = "a502d807813eec10884105b00e7c6e6031914565";
      hash = "sha256-TuoFeYK2uetxOBZI9qE8X0EYX/saluXa8ju6ll3KxLc=";
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
      rev = "bab040941390f6c1e82c0508ec806f2fc8255cbb";
      hash = "sha256-sM7V/IkyuHUmhew97NZUJGVOc9KLpBtw2FnuMfHQG0k=";
      plugins = {
        claude-mem = {
          version = "15.1.0";
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
      rev = "1ecea1993b7fce257ffbd686c070948b5e07eda6";
      hash = "sha256-GTqrnZxQvzo/ogAuUrffkOaMK1BYm/4rAZsnfmDt7DU=";
      skillsSubpath = "skills";
    };
    # REA ships an npm package, not a plugin: the skill is pinned here and the
    # MCP server (below, `mcpServers.rea`) runs the npm release cut from the
    # same tag, so instructions and tools stay in step. Bump both together.
    # autoUpdate = false keeps update-deps from moving this to upstream HEAD,
    # which runs ahead of the npm release (and once broke the build by moving
    # the skill dir). `skills` drops the dev-only skills that share the dir.
    rea = {
      owner = "morluto";
      repo = "rea";
      rev = "a56f7bb668ab23fec8d33f7af353ac7ed2fe1895"; # rea-agents-6.4.0
      hash = "sha256-aAbOYpsT6QhlLAZDtVHZ1Acz6uIqrVEd4p49s/2FJgc=";
      skillsSubpath = ".agents/skills";
      skills = ["reverse-engineer-anything"];
      autoUpdate = false;
    };
  };

  # ─── MCP servers shared by Claude Code and Cursor ───────────────────────
  # Servers that don't come from a plugin's .mcp.json. claude-code.nix merges
  # them into ~/.claude.json, cursor.nix into ~/.cursor/mcp.json.
  mcpServers = {
    # Ghidra is REA's native-analysis provider (it checks for 12.1.x). Paths
    # are passed explicitly: MCP servers don't inherit a login shell's PATH.
    rea = {
      type = "stdio";
      command = "${pkgs.nodejs}/bin/npx";
      args = ["-y" "rea-agents@6.4.0" "mcp"];
      env = {
        GHIDRA_INSTALL_DIR = "${pkgs.ghidra}/lib/ghidra";
        JAVA_HOME = "${pkgs.openjdk21}/lib/openjdk";
      };
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

  # A repo with `skills` contributes only those <name>/ dirs; otherwise its
  # whole skills dir is joined in. The filtered dirs are copied as real dirs
  # of file symlinks (cp -rs), not wrapSkillDir's single dir symlink: the
  # trees are linked with `recursive = true`, so a skill that was a real dir
  # in ~/.claude/skills would collide with a symlink and fail activation.
  skillRepoDirs = lib.mapAttrsToList (name: r: let
    root =
      if r.skillsSubpath == ""
      then skillRepoSrcs.${name}
      else "${skillRepoSrcs.${name}}/${r.skillsSubpath}";
  in
    if r ? skills
    then
      pkgs.runCommand "${name}-skills" {} ''
        mkdir $out
        ${lib.concatMapStrings (s: "cp -rs ${root}/${s} $out/\n") r.skills}
      ''
    else root)
  skillRepos;

  # Skills written in this repo (<name>/SKILL.md dirs), not pinned upstream.
  localSkillsDir = ./claude-files/skills;

  joinTree = name: paths: pkgs.symlinkJoin {inherit name paths;};
in {
  inherit marketplaces skillRepos marketplaceSrcs skillRepoSrcs pluginEntries pluginRoots mcpServers;

  # Claude Code loads plugin skills through the plugin loader (namespaced as
  # `plugin:skill`), so only the plain skill repos and local skills go in
  # ~/.claude/skills.
  claudeSkillsTree = joinTree "claude-skills" (skillRepoDirs ++ [localSkillsDir]);

  # Cursor has no plugin loader: flatten repo skills *and* plugin skills into
  # one tree so ~/.cursor/skills ends up with the same skill set.
  cursorSkillsTree =
    joinTree "cursor-skills"
    (skillRepoDirs ++ [localSkillsDir] ++ pluginDirs "skillsSubpath" ++ pluginRootSkillDirs);

  # Plugin slash-commands, for ~/.cursor/commands.
  cursorCommandsTree = joinTree "cursor-commands" (pluginDirs "commandsSubpath");
}
