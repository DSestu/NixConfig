# pr-dash V1 — tasks

Plan: `plan.md`. Spec: `../SPEC.md`.
Dev loop (from `modules/home/dev/pr-dash`):
`nix-shell -p go --command "go build ./... && go test ./..."`.
Nix builds and switches go through a subagent, as CLAUDE.md requires.

## Task 1: Skeleton binary builds with Nix and is on PATH

**Description:** Add `go.mod` with the spec's dependencies, a `main.go` that
prints a version line, and `default.nix` (`buildGoModule`; get `vendorHash`
from the build error). Wire it in as `(callPackage ./dev/pr-dash {})` in
`modules/home/dev.nix`.

**Acceptance criteria:**
- [x] `go build ./...` passes
- [x] The home-manager build includes `pr-dash`, and `pr-dash --version` prints a version line

**Verification:**
- [x] A subagent runs `nix build` on the host config and reports success

**Dependencies:** None
**Files:** `go.mod`, `go.sum`, `main.go`, `default.nix`, `modules/home/dev.nix`
**Scope:** S

## Task 2: Live GraphQL fetch, parsed into model types

**Description:** `internal/gh` resolves the repo from the cwd remote via go-gh
and runs the single query from the spec. `internal/model` holds the PR,
Check, Comment and Stack types. Record a fixture from the real response.
`pr-dash --dump` prints one line per PR: number, title, check state,
mergeable state and stack position.

**Acceptance criteria:**
- [x] `--dump` in NixConfig lists the same numbers as `gh pr list`
- [x] The parse test passes against `testdata/prs.json`
- [x] Any stack fields that fail are documented, and the query is fixed

**Verification:**
- [x] `go test ./internal/...`
- [x] Compare `pr-dash --dump` with `gh pr list` by hand

**Dependencies:** 1
**Files:** `internal/gh/query.go`, `internal/gh/client.go`, `internal/model/pr.go`, `internal/gh/parse_test.go`, `internal/gh/testdata/prs.json`
**Scope:** M

### Checkpoint A: the Nix build and live data both work. Review before the UI work.

## Task 3: Rail + table + preview layout in Charm Glow, with real data

**Description:** Build the Bubble Tea model with the three columns, the header,
the merge bar line and the footer. `theme.go` holds the Charm Glow tokens and
the glyph map. `tab` cycles focus between panels; `j/k` and the arrow keys
move the cursor; `q` quits. For now the preview shows the title and meta only.

**Acceptance criteria:**
- [x] At 150×42 it matches `rail-three-col.html` + `charm-glow.html`, with no broken borders
- [x] The focused panel has the violet border; the other panels are dimmed

**Verification:**
- [x] Manual check in a 150×42 tmux pane, side by side with the mockup

**Dependencies:** 2
**Files:** `internal/ui/model.go`, `internal/ui/view.go`, `internal/ui/theme.go`, `main.go`
**Scope:** M

## Task 4: Stack grouping and rail section filters

**Description:** Pure functions in `internal/model`:
- group PRs by stack and order them by position;
- filter by section: All, Mine, Bumps, Stacks, Review, Failing, Conflicts.

The table renders stacks as `├ └` rows with `n/size`. The rail counts update
live, and selecting a rail section filters the table.

**Acceptance criteria:**
- [x] Unit tests cover grouping and each filter
- [x] Stack rows show their indent and positions; Failing and Conflicts filter correctly

**Verification:**
- [x] `go test ./internal/model/`
- [x] Check by hand against the live repo

**Dependencies:** 3
**Files:** `internal/model/stack.go`, `internal/model/filter.go`, `internal/model/*_test.go`, `internal/ui/view.go`
**Scope:** M

## Task 5: Rich preview

**Description:** The preview panel shows:
- meta chips;
- checks with their state and duration;
- the body rendered by glamour, with a theme matched to Charm Glow;
- the last comments;
- mergeable/conflict state.

The preview scrolls when focused.

**Acceptance criteria:**
- [x] Spec success criterion 4 passes
- [x] Long bodies scroll without overflowing the right edge

**Verification:**
- [x] Manual check on a PR with a body, comments and failing checks

**Dependencies:** 3
**Files:** `internal/ui/preview.go`, `internal/ui/theme.go`
**Scope:** S

## Task 6: Auto-refresh

**Description:** A `tea.Tick` refetches every 60 s, and `r` forces a refetch.
The header shows the countdown and a spinner while fetching. Cursor and marks
survive a refresh, keyed by PR number. A fetch error shows in the header and
keeps the old data.

**Acceptance criteria:**
- [x] Spec success criterion 3 passes
- [x] With the network off, an error shows and the app does not crash

**Verification:**
- [x] Manual check: wait for a refresh, press `r`, then switch the network off and on

**Dependencies:** 3
**Files:** `internal/ui/model.go`
**Scope:** S

### Checkpoint B: the read-only TUI is complete. Spec criteria 1, 2, 3, 4 and 7 pass by hand. Review before merge work.

## Task 7: Marking + merge plan + `--dry-run`

**Description:** `space` toggles a mark. Marking stack position N implies
1..N−1, and the merge bar shows the marked count. A pure
`model.BuildPlan(prs, marked)` returns:
- ordered merge steps, one step per stack, submitted on its top marked PR;
- skips with reasons: failing checks, conflicting, draft.

With `--dry-run`, pressing `M` shows the plan and never calls a write endpoint.

**Acceptance criteria:**
- [x] Table tests cover stack implication, skip reasons and ordering
- [x] `--dry-run` + `M` shows the plan, and no write request is made

**Verification:**
- [x] `go test ./internal/model/`

**Dependencies:** 4
**Files:** `internal/model/plan.go`, `internal/model/plan_test.go`, `internal/ui/model.go`, `main.go`
**Scope:** M

## Task 8: Confirm dialog, merge-async client, progress, summary, DSestu guard

**Description:** `M` opens a confirm dialog listing what merges and what is
skipped, and why. `y` runs the steps in order: `PUT .../merge-async` with
`{"merge_method":"squash"}`, then polls until the request is no longer
pending. The UI shows progress for each PR and ends with a summary, including
any conflict failures. Outside a `DSestu/*` repo, `M` refuses with a message.
It never uses admin merge.

**Acceptance criteria:**
- [x] Spec success criteria 5 and 6 pass
- [x] A merge failure for one PR does not stop the rest; the summary lists it

**Verification:**
- [x] Client test with an `httptest` server: pending → merged, and pending → failed
- [x] Manual check: one real single-PR merge first, then a bump batch

**Dependencies:** 7
**Files:** `internal/gh/merge.go`, `internal/gh/merge_test.go`, `internal/ui/confirm.go`, `internal/ui/model.go`
**Scope:** M

### Checkpoint C: run a dry run, then one real bump batch in NixConfig, and review the results.

## Task 9: The `ws` pane runs pr-dash

**Description:** In the `ws` function in `modules/dual/fish.nix`, replace
`'gh dash'` with `'pr-dash'`. The layout stays the same, and `diffnav --watch`
stays below.

**Acceptance criteria:**
- [x] Spec success criterion 8 passes (build-verified; live ws check pending)

**Verification:**
- [x] A subagent runs the switch build
- [ ] Manual check: run `ws` in NixConfig

**Dependencies:** 8
**Files:** `modules/dual/fish.nix`
**Scope:** XS

## Task 10: Responsive layout, mouse and motion

**Description:**
- Below 110 columns, the rail collapses to a one-line section switcher.
- A mouse click selects a row or rail section; the wheel scrolls.
- The cursor glides with a harmonica spring.
- Merge progress animates.

All motion is short and never delays input.

**Acceptance criteria:**
- [ ] Spec success criterion 9 passes, at both 150×42 and 110 columns
- [x] Mouse click and wheel work in tmux (done with Task 8; unit-tested, live check pending)

**Verification:**
- [ ] Manual check: resize the tmux pane

**Dependencies:** 6, 8
**Files:** `internal/ui/view.go`, `internal/ui/model.go`, `internal/ui/motion.go`
**Scope:** M

### Checkpoint D: done when:
- [ ] all 9 success criteria pass;
- [ ] the impeccable finish review has run and its fixes are applied;
- [ ] DESIGN.md is written;
- [ ] the diff is staged and shown. Commit only after "commit".
