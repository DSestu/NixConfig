# NixConfig — Conventions for Claude Code

## Architecture

Read `CONTRIBUTING.md` for the four-principle mental model (one flake
many profiles; HM vs NixOS split; impermanence is a property of the
running system; disko is opt-in via the host folder). Don't violate
those principles without asking.

For active work and remediation scope, see `SPEC.md`.

## Running Nix commands — always via a subagent

`nix build`, `nix flake check`, `nixos-rebuild`, `nix shell`, and `nix
develop` produce hundreds to thousands of lines of output (download
progress, builder logs, evaluation traces). Running them in the main
conversation burns the context budget and crowds out the actual work.

**Rule:** delegate every nix command that compiles, evaluates a full
flake, or downloads anything to a temporary subagent via the `Agent`
tool. The subagent runs the command, parses the output, and reports
back a one-paragraph summary (success/failure, the relevant error if
any, the derivation path if useful).

Examples that **must** be delegated:
- `nix build .#nixosConfigurations.<name>.config.system.build.toplevel`
- `nix build .#nixosConfigurations.<name>.config.system.build.vm`
- `nix flake check` (with or without `--no-build`)
- `nixos-rebuild build|switch|test`
- `nix shell <pkg> --command <something-noisy>`
- `nix develop` (for entering a dev shell to run a build)
- Anything piped through `nom` / `nix-output-monitor`

Examples that are **fine** to run directly (small, bounded output):
- `nix eval .#nixosConfigurations.<name>.config.<some.option>`
- `nix flake metadata`
- `nix-store --query` / `nix path-info`
- `nix flake show` (just lists outputs)

**Subagent prompt template:**
```
Run `<exact command>` from /home/david/github/NixConfig.
Report in under 100 words: did it succeed? If not, the single most
relevant error line and the file:line it points to. If it built,
the output store path. Do not paste full logs.
```

Use `general-purpose` or `Explore` as the subagent type — they have
Bash access and won't pollute the parent context with the build
transcript.

## Tools

- `rg` (ripgrep) not `grep`; `fd` not `find` (per global rules).
- Prefer dedicated tools (Read/Edit/Grep/Glob) over Bash for file ops.

## Memory bank

Per `~/.claude/CLAUDE.md`, this repo uses the CLAUDE-\*.md memory bank
pattern. Read on demand; sync after significant work.

## Boundaries reminder

- Never re-enable root SSH login or SSH password authentication.
- Never land an `impermanence = true` profile without a working wipe
  mechanism (the bug `SPEC.md` exists to prevent).
- Ask before destructive git or destructive nix-store operations.
