# Spec: pr-dash — V1

Status: approved 2026-11-22

`pr-dash` is the working name; the final name is still open. Product truth lives
in `PRODUCT.md` next to this file.

## Objective

Replace gh-dash in the `ws` tmux workspace with a custom PR TUI for the current
repo. Its user is David, triaging and landing his own PRs and the bot bump PRs
without a browser.

User stories:

1. I see every open PR of the current repo, and the list refreshes by itself.
2. I see gh-stack stacks: which PRs belong together, and in what order.
3. For the selected PR I see its body, comments, CI checks (with durations), and
   whether it can merge or has conflicts.
4. I mark several PRs with `space` and squash-merge them in one batch after a
   single confirmation. Marking a PR in a stack implies the PRs below it.
5. Problem PRs are one keystroke away: failing checks and conflicts each have a
   section in the rail.

## Approved design (impeccable rounds, 2026-11-19)

- **Layout: section rail, three columns**
  (`.impeccable/mocks/decision/surface/rail-three-col.html`).
  - Context header line.
  - Left rail (about 20 cols) of sections with counts: All, Mine, Bumps, Stacks,
    Review, Failing, Conflicts, then Marked.
  - PR table in the middle (about 72 cols), with columns mk, #, title, ck, ±, age.
    Stack rows are indented ├ └ and show 1/3.
  - Preview on the right (about 58 cols): meta, checks, body, comments.
  - A one-line merge bar, then a footer of key hints.
  - The focused panel is highlighted; `tab` cycles panels.
- **Look: Charm Glow** (`.impeccable/mocks/decision/theme/charm-glow.html`).
  - Colours: violet-black ground `#16121f`, text `#e8e3f5`, dim `#6e6585`,
    pink `#ff5fd2`, violet `#9d7cff`, mint `#5fe3b0` for pass, coral `#ff6b81`
    for fail, amber `#ffcf5c` for running and marked.
  - Title is a pink→violet gradient pill.
  - The focused panel has a violet rounded border and a violet title tab; the
    other panels are dimmed.
  - Status labels are chips.
  - Marked PRs show an amber ●.
  - Emoji become 1-cell glyphs: ❄→*, 🤖→◆, 📌→▲, ✨→✦, 🌐→◎.
- Rejected: the Flight Strip, Gate Board and Transit directions; the Stack lanes
  and Merge tray layouts; the Borderless, Mono and Warm Amber looks.

## Tech Stack

- Go
- `charm.land/bubbletea/v2` v2.1.x
- `charm.land/lipgloss/v2` v2.1.x
- `charm.land/bubbles/v2` v2.2.x
- `charm.land/glamour/v2` v2.0.x
- `github.com/charmbracelet/harmonica`
- `github.com/cli/go-gh/v2` for the auth token and the GraphQL/REST clients

These versions are the ones the throwaway demo compiled against.

## Data and API

- **Read:** one GraphQL query per refresh. It fetches
  `repository.pullRequests(states: OPEN)` with number, title, author, createdAt,
  additions/deletions, body, comments(last N), mergeable, mergeStateStatus,
  `statusCheckRollup` contexts (name, state, duration), and
  `stack { number size }` plus `stackEntry.position`. Checked live on
  2026-11-22: `stack.entries` is a connection with no `position`, so stacks are
  grouped by `stack.number` and ordered by each PR's own `stackEntry.position`.
  `mergeable` comes back UNKNOWN on the first query and settles on the next one.
  Bot bump PRs have no checks, because GITHUB_TOKEN pushes trigger no workflows.
- **Merge, single or bump:** `PUT /repos/{o}/{r}/pulls/{n}/merge-async` with
  `{"merge_method":"squash"}`, then poll
  `GET .../merge-async/{uuid}` until the request leaves `pending`.
- **Merge a stack:** submit `merge-async` once, on the highest marked PR. It
  merges that PR and everything below it atomically.
- **Repo:** taken from the cwd's git remote, the same way `gh` picks it.

## Commands

```
Dev build: cd modules/home/dev/pr-dash && nix-shell -p go --command "go build ./... && go test ./..."
Run:       ./pr-dash          (inside a GitHub repo)
Nix:       buildGoModule derivation in modules/home/dev/pr-dash/default.nix; vendorHash via fake-hash error
Switch:    home-manager / nixos-rebuild build    # via subagent per CLAUDE.md
```

## Project Structure

```
modules/home/dev/pr-dash/
  PRODUCT.md, SPEC.md      product truth + this spec
  default.nix              buildGoModule derivation (callPackage'd from dev.nix, like dmux)
  go.mod, go.sum
  main.go                  program entry, flags (--dry-run)
  internal/gh/             GraphQL query, merge-async client (pure, testable)
  internal/model/          PR/stack types, selection & merge-plan logic (pure)
  internal/ui/             bubbletea model, views, theme (Charm Glow tokens)
modules/dual/fish.nix      ws: replace 'gh dash' pane with pr-dash
modules/home/dev.nix       remove programs.gh-dash
```

## Code Style

Follow the repo's existing Go code style; if it has none, use `gofmt` and the
small-package layout above.
- Theme colours are named lipgloss constants in a single `theme.go` and are not
  repeated anywhere else.
- The UI never calls GitHub directly; it sends `tea.Cmd`s that return messages.

## Testing Strategy

- **Unit tests** (`go test`) for the pure logic:
  - building the merge plan: stack-implied selection, skipping failing or
    conflicting PRs with a reason, and the merge order;
  - grouping PRs by stack;
  - parsing the GraphQL response against a recorded JSON fixture.
- **`--dry-run`:** prints the merge plan and calls no write endpoint.
- **Manual check:** in NixConfig with real bump PRs. Do a dry run first, then
  one real batch.

## Boundaries

- Always: one confirmation per batch that lists exactly what will merge and what
  will be skipped and why; `--dry-run` works.
- Ask first: new Go dependencies beyond the stack above; changing the `ws`
  layout beyond swapping the pane command; removing `programs.gh-dash`.
- Never:
  - merge in a repo not owned by `DSestu`;
  - use admin merge or bypass checks or branch protection;
  - store the token anywhere (`go-gh` reads it from gh).

## Success Criteria

1. In NixConfig, `pr-dash` shows every open PR, matching `gh pr list` in count
   and numbers, in the rail layout and the Charm Glow look.
2. Stacked PRs appear as ├ └ rows with their positions. Marking position N
   marks 1..N−1.
3. The list refreshes on its own at the configured interval. The header shows
   the time to the next refresh, and `r` forces a refresh.
4. The preview shows the body (rendered markdown), comments, checks with state
   and duration, and mergeable/conflict state.
5. Pressing `M` with marked PRs shows a confirmation listing what merges and
   what is skipped (failing checks, conflicts). `y` merges them in plan order,
   shows progress for each PR, and ends with a summary.
6. In a repo not owned by DSestu, `M` refuses with a message.
7. The rail's Failing and Conflicts sections each filter the table.
8. The `ws` right pane runs `pr-dash` instead of gh-dash, and `diffnav` still
   sits below it.
9. It fits a tmux pane of 150×42 without broken borders, and at 110 columns the
   rail collapses.

## Out of Scope (Deferred)

- Issues and notifications.
- Multi-repo view: V1 shows the current repo only.
- Review actions (approve, comment) from the TUI.
- Mouse hover effects beyond click-to-select and wheel scrolling.
- Spring animations beyond the cursor glide and merge progress.

## Resolved Questions

1. **Bump conflicts:** skip and report; the next update-deps run regenerates them.
2. **Refresh interval:** 1 minute.
3. **Final name:** `pr-dash` until renamed; renaming is a later one-line change.
4. **gh-dash:** stays installed in V1. Removing `programs.gh-dash` is a separate,
   asked-for change once pr-dash has replaced it in daily use.
