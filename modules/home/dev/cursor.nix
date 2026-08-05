{
  pkgs,
  lib,
  ...
}: let
  # Same pinned upstreams Claude Code gets — see ./agent-sources.nix.
  sources = import ./agent-sources.nix {inherit pkgs lib;};

  # ─── Rules ──────────────────────────────────────────────────────────────
  # Cursor's equivalent of an always-loaded CLAUDE.md is a `.mdc` file in
  # ~/.cursor/rules with `alwaysApply: true` (verified against cursor-agent:
  # a file rule with alwaysApply becomes a "global" rule, description or not).
  # Bodies are the *same* files Claude reads, verbatim — mirroring means the
  # Claude-specific wording (memory bank, /memory) comes along too.
  #
  # Project-level instructions need no mirroring: Cursor natively loads
  # AGENTS.md, CLAUDE.md and CLAUDE.local.md from the workspace.
  mkRule = description: file: {
    text =
      ''
        ---
        description: ${description}
        alwaysApply: true
        ---

      ''
      + builtins.readFile file;
  };

  # ─── i-have-adhd always-on ──────────────────────────────────────────────
  # Claude Code gets this ruleset from the skill's SessionStart hook (see
  # ./claude-code.nix). Cursor runs no hooks, so the same SKILL.md body is
  # turned into an alwaysApply rule. Built in a derivation rather than with
  # builtins.readFile so evaluation doesn't have to fetch the repo (no IFD).
  adhdSkill = "${sources.skillRepoSrcs.i-have-adhd}/skills/i-have-adhd/SKILL.md";

  adhdRule = pkgs.runCommand "i-have-adhd.mdc" {} ''
    {
      printf -- '---\ndescription: %s\nalwaysApply: true\n---\n\n' \
        'ADHD-friendly output — lead with the next action, number steps, suppress tangents'
      # Drop SKILL.md's own YAML frontmatter; keep the ruleset body.
      awk '
        NR == 1 && $0 ~ /^---[[:space:]]*$/ { in_fm = 1; next }
        in_fm && $0 ~ /^---[[:space:]]*$/   { in_fm = 0; next }
        !in_fm                              { print }
      ' ${adhdSkill}
    } > $out
  '';

  # ─── claude-mem MCP ─────────────────────────────────────────────────────
  # Claude gets this server from the plugin's .mcp.json; Cursor has no plugin
  # loader, so point it straight at the same entrypoint. Both agents then
  # share one memory store (~/.claude-mem/claude-mem.db) — Cursor can search
  # what Claude recorded and vice versa.
  memRoot = sources.pluginRoots."claude-mem@thedotmack";

  mcpAddition = {
    mcpServers.claude-mem = {
      type = "stdio";
      command = "${pkgs.nodejs}/bin/node";
      args = ["${memRoot}/scripts/mcp-server.cjs"];
    };
  };
in {
  home.file = {
    # `recursive` so these coexist with Cursor's own bundled skills and with
    # anything created via Cursor's create-skill / create-rule flows.
    ".cursor/skills" = {
      source = sources.cursorSkillsTree;
      recursive = true;
    };
    ".cursor/commands" = {
      source = sources.cursorCommandsTree;
      recursive = true;
    };
    ".cursor/rules/claude-global.mdc" =
      mkRule "Global engineering instructions (mirrored from ~/.claude/CLAUDE.md)"
      ./claude-files/CLAUDE.md;
    ".cursor/rules/core-rules.mdc" =
      mkRule "Core working rules: investigation, scope, verification, git"
      ./claude-files/rules/core-rules.md;
    ".cursor/rules/i-have-adhd.mdc".source = adhdRule;
  };

  # ~/.cursor/mcp.json is hand-maintained (it carries a postgres server whose
  # DATABASE_URI is a live credential that must not enter this repo), so the
  # claude-mem entry is merged in rather than the file being overwritten.
  # jq's `*` is a recursive merge: other servers survive, ours is re-asserted.
  home.activation.cursorMcpServers = lib.hm.dag.entryAfter ["writeBoundary"] ''
    install -d -m 0700 "$HOME/.cursor"
    if [ ! -s "$HOME/.cursor/mcp.json" ]; then
      echo '{}' | install -m 0600 /dev/stdin "$HOME/.cursor/mcp.json"
    fi
    _cursor_mcp_tmp=$(mktemp)
    ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$HOME/.cursor/mcp.json" /dev/stdin \
      > "$_cursor_mcp_tmp" <<'JSON'
    ${builtins.toJSON mcpAddition}
    JSON
    install -m 0600 "$_cursor_mcp_tmp" "$HOME/.cursor/mcp.json"
    rm -f "$_cursor_mcp_tmp"
  '';
}
