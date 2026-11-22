# Implementation Plan: pr-dash V1

Source spec: `modules/home/dev/pr-dash/SPEC.md` (approved 2026-11-22).
Task details: `tasks/todo.md` next to this file. The repo-root `tasks/` belongs
to the finished `ns` plan and is left alone.

## Overview

A Go + Bubble Tea v2 TUI that replaces gh-dash in the `ws` pane: open PRs of
the current repo with stacks, auto-refresh every minute, a rich preview, and
batch squash-merge through `merge-async`. Built in thin vertical slices: each
task ends with a binary that runs and shows more than the last one.

## Architecture Decisions

- **Packaging like dmux:** `default.nix` is a plain `buildGoModule` derivation,
  wired as `(callPackage ./dev/pr-dash {})` in `modules/home/dev.nix`. It is
  built first (Task 1) because `vendorHash` and the nixpkgs Go version are the
  main way this could fail late.
- **Three packages, one direction:** `internal/gh` (I/O) → `internal/model`
  (pure types, grouping, filters, merge plan) ← `internal/ui` (Bubble Tea).
  The UI only touches GitHub through `tea.Cmd`s.
- **The GraphQL query is checked against the live API in Task 2**, before any UI
  is built on it. The `stack` and `stackEntry` fields are the part most likely to
  differ from the docs.
- **Conflicting bumps are not predicted.** The batch merges in order. A PR
  whose merge fails with a conflict is recorded as skipped, with the reason.
- **gh-dash stays installed.** Only the `ws` pane command changes.

## Task List

### Phase 1: Foundation (risk first)
- [x] Task 1: Skeleton binary builds with Nix and is on PATH
- [x] Task 2: Live GraphQL fetch, parsed into model types (`--dump`)

### Checkpoint A
- [x] `nix build` OK; `pr-dash --dump` in NixConfig matches `gh pr list`

### Phase 2: Read-only TUI
- [x] Task 3: Rail + table + preview layout in Charm Glow, with real data
- [x] Task 4: Stack grouping and rail section filters
- [x] Task 5: Rich preview: markdown body, checks with durations, comments, mergeable
- [x] Task 6: Auto-refresh every minute, header countdown, `r`

### Checkpoint B
- [ ] Spec success criteria 1, 2, 3, 4 and 7 pass by hand in NixConfig

### Phase 3: Merge
- [x] Task 7: Marking + pure merge plan (tests) + `--dry-run`
- [x] Task 8: Confirm dialog, merge-async client, progress, summary, DSestu guard

### Checkpoint C
- [ ] Dry run first, then one real bump batch in NixConfig; criteria 5 and 6 pass

### Phase 4: Integration and polish
- [x] Task 9: `ws` pane runs pr-dash
- [ ] Task 10: Collapse at 110 cols, cursor glide, merge-progress motion (mouse done early, on request)

### Checkpoint D (done)
- [ ] All 9 success criteria pass
- [ ] impeccable finish review fixes applied; DESIGN.md recorded
- [ ] Diff staged and shown; commit only on "commit"

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| nixpkgs Go older than what Bubble Tea v2 needs | High | Task 1 builds first; if needed, pin `buildGoModule.override { go = pkgs.go_1_xx; }` |
| `stack`/`stackEntry` fields differ from docs or need a preview header | High | Task 2 queries the live API first; adjust the query before any UI exists |
| `merge-async` response shape differs from docs | Med | Task 8 starts with one real single-PR merge, behind the confirm dialog |
| `mergeable` is UNKNOWN right after a merge | Med | Show it as "checking", not conflict; the next refresh settles it |
| Emoji width breaks borders | Med | Map title emoji to 1-cell glyphs (spec table); test at 150×42 |
| Truecolor off in tmux | Low | lipgloss downsamples; check once in the `ws` pane |

## Open Questions

None. All four spec questions are resolved in SPEC.md.
