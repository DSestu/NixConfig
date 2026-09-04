# Code-Graph-RAG — an MCP server that parses a monorepo with Tree-sitter into
# a Memgraph knowledge graph, then answers structural questions about it
# (callers, callees, implementors, tests_reaching, duplicate code, …) plus
# natural-language queries over the graph.
#
# Unlike everything else under dev/, this is neither a plugin nor a skill: it
# is a stdio MCP server, so it is registered for both agents by hand — the
# ~/.claude.json merge below and the ~/.cursor/mcp.json merge at the bottom.
#
# ─── Runtime, and why it is not a nix build ──────────────────────────────
# Upstream ships to PyPI and recommends `uvx`. Building the Python package
# here would mean packaging pymgclient (needs cmake + the C mgclient lib),
# tree-sitter grammars for every supported language, and pydantic-ai — for a
# tool whose version moves several times a week. So this follows the precedent
# set by ./dbhub.nix: let the ecosystem's own resolver fetch it at launch,
# pinned to an exact version rather than @latest so a rebuild does not silently
# change which server the agents talk to. `uv` comes from ../dev.nix.
#
# ─── Prerequisites the module cannot supply ──────────────────────────────
# 1. The graph store. Memgraph + Qdrant run in Docker; upstream wraps them:
#      cgr daemon up          # from a checkout, or `uvx code-graph-rag daemon up`
#    Without it every tool call fails to connect on localhost:7687.
# 2. A repository has to be indexed once (`index_repository`, then
#    `update_repository` / `reingest` for deltas). TARGET_REPO_PATH is
#    auto-detected from the working directory, so it is deliberately not set
#    here — one server definition serves every project.
# 3. LLM credentials for the orchestrator / Cypher-generation agents. Those
#    are secrets, and both home.file and activation heredocs land in the
#    world-readable /nix/store, so they are read at launch from
#    ~/.config/code-graph-rag/env (create by hand, mode 0600):
#
#      ORCHESTRATOR_PROVIDER=anthropic
#      ORCHESTRATOR_MODEL=claude-opus-5
#      ORCHESTRATOR_API_KEY=sk-ant-…
#      CYPHER_PROVIDER=anthropic
#      CYPHER_MODEL=claude-haiku-4-5-20251001
#      CYPHER_API_KEY=sk-ant-…
#
#    The file is optional: with it absent the server falls back to upstream's
#    defaults (a local ollama/llama3.2), and the deterministic graph tools
#    (resolve/definition/callers/…) need no LLM at all.
{
  config,
  pkgs,
  lib,
  ...
}: let
  # Bump deliberately; check https://pypi.org/project/code-graph-rag/.
  version = "0.0.845";

  envFile = "${config.home.homeDirectory}/.config/code-graph-rag/env";

  # `set -a` exports everything the env file assigns, so the sourced values
  # reach the exec'd server; the `[ -f ]` guard keeps a missing file harmless.
  launcher = pkgs.writeShellScript "code-graph-rag-mcp" ''
    set -a
    [ -f ${lib.escapeShellArg envFile} ] && . ${lib.escapeShellArg envFile}
    set +a
    exec ${pkgs.uv}/bin/uvx "code-graph-rag@${version}" mcp-server "$@"
  '';

  mcpServers.code-graph-rag = {
    type = "stdio";
    command = "${launcher}";
    args = [];
  };

  serversJSON = builtins.toJSON mcpServers;
in {
  # Same reason as ./dbhub.nix: ~/.claude.json carries mutable session state,
  # so merge the one key instead of replacing the file. Distinct activation
  # attribute name so it composes with dbhub's block rather than colliding.
  home.activation.claudeCodeMcpCodeGraphRag = lib.hm.dag.entryAfter ["writeBoundary"] ''
    claude_json="$HOME/.claude.json"
    [ -f "$claude_json" ] || install -m 0600 /dev/stdin "$claude_json" <<<'{}'
    ${pkgs.jq}/bin/jq --argjson servers ${lib.escapeShellArg serversJSON} \
      '.mcpServers = (.mcpServers // {}) * $servers' \
      "$claude_json" > "$claude_json.hm-cgr-tmp"
    install -m 0600 "$claude_json.hm-cgr-tmp" "$claude_json"
    rm -f "$claude_json.hm-cgr-tmp"
  '';

  # Cursor side of the agent-parity rule (see CLAUDE.md): ~/.cursor/mcp.json is
  # hand-maintained and holds a live credential, so merge rather than write.
  home.activation.cursorMcpCodeGraphRag = lib.hm.dag.entryAfter ["writeBoundary"] ''
    install -d -m 0700 "$HOME/.cursor"
    if [ ! -s "$HOME/.cursor/mcp.json" ]; then
      echo '{}' | install -m 0600 /dev/stdin "$HOME/.cursor/mcp.json"
    fi
    _cgr_mcp_tmp=$(mktemp)
    ${pkgs.jq}/bin/jq --argjson servers ${lib.escapeShellArg serversJSON} \
      '.mcpServers = (.mcpServers // {}) * $servers' \
      "$HOME/.cursor/mcp.json" > "$_cgr_mcp_tmp"
    install -m 0600 "$_cgr_mcp_tmp" "$HOME/.cursor/mcp.json"
    rm -f "$_cgr_mcp_tmp"
  '';
}
