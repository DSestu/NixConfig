# DBHub — one MCP server fronting every Sencrop database (Postgres + MySQL).
#
# Why DBHub rather than one MCP server per engine: sources are named, and the
# id lands in the generated tool name (execute_sql_dwh_preprod vs
# execute_sql_back_prod), so the agent cannot confuse preprod with prod. Two
# tools per source keeps the context cost flat as databases are added.
#
# ─── Credentials ─────────────────────────────────────────────────────────
# The connection strings live in ~/.config/dbhub/dbhub.toml, which is
# deliberately NOT managed here: home.file and activation heredocs both end up
# in the world-readable /nix/store. This module only registers the server and
# points at that path. Create it by hand (mode 0600) — see dbhub.toml.example
# in the DBHub repo, or copy from ~/github/tools/tools_perso/.env.
#
# To make it declarative later, encrypt it as secrets/dbhub-config.age
# (publicKeys = allHosts) and read config.age.secrets."dbhub-config".path
# instead — the cachix-auth-token secret is the precedent for a user-readable
# agenix secret. That needs agenix wired into homeConfigurations."david",
# which today only gets the NixOS module, so it is a follow-up.
#
# ─── Databricks ──────────────────────────────────────────────────────────
# Not handled here: DBHub speaks Postgres/MySQL/MariaDB/SQL Server/SQLite only.
# Databricks managed MCP servers authenticate via OAuth, not the PAT in .env:
#   uv tool install git+https://github.com/databricks/ucode
#   ucode mcp add --agents claude --services <catalog>.<schema>.<service>
# The claude.ai Databricks connector is the zero-setup alternative.
{
  config,
  pkgs,
  lib,
  ...
}: let
  dbhubConfig = "${config.home.homeDirectory}/.config/dbhub/dbhub.toml";

  mcpServers.dbhub = {
    type = "stdio";
    command = "${pkgs.nodejs}/bin/npx";
    args = [
      "-y"
      "@bytebase/dbhub@latest"
      "--transport"
      "stdio"
      "--config"
      dbhubConfig
    ];
  };
in {
  # `claude mcp add -s user` writes into ~/.claude.json, which also holds
  # mutable session state (history, project list), so it cannot be replaced
  # wholesale like settings.json is in ./claude-code.nix. Merge the one key
  # instead, and re-assert it on every activation.
  home.activation.claudeCodeMcpServers = lib.hm.dag.entryAfter ["writeBoundary"] ''
    claude_json="$HOME/.claude.json"
    [ -f "$claude_json" ] || install -m 0600 /dev/stdin "$claude_json" <<<'{}'
    ${pkgs.jq}/bin/jq --argjson servers ${
      lib.escapeShellArg (builtins.toJSON mcpServers)
    } '.mcpServers = (.mcpServers // {}) * $servers' \
      "$claude_json" > "$claude_json.hm-tmp"
    install -m 0600 "$claude_json.hm-tmp" "$claude_json"
    rm -f "$claude_json.hm-tmp"
  '';
}
