# Product

<!-- impeccable:product-schema 1 -->

## Platform

terminal (TUI in a tmux pane; not web/ios/android)

## Stack

Go, Bubble Tea v2 + lipgloss v2 + bubbles v2 + glamour v2 + harmonica.
Packaged with `buildGoModule` inside NixConfig (`modules/home/dev/pr-dash/`).
Working name `pr-dash`, final name undecided.

## Users

One user: David, the repo owner, working in his `ws` tmux workspace
(1/4 terminals | 3/4 PR pane over `diffnav --watch`). He triages and lands his
own PRs and the bot bump PRs without opening a browser.

## Product Purpose

It replaces gh-dash in `ws`. For the current repo it shows open PRs, including
gh-stack stacks, and refreshes on its own. For each PR it shows the body,
comments, CI checks and mergeable/conflict state. Several PRs can be selected
and squash-merged in one batch. Success means landing a morning's batch of bump
PRs takes a few keystrokes and no browser.

## Positioning

gh-dash has no multi-select and no stack view (upstream issue #956 is open).
This tool is stack-aware: selecting PR N of a stack implies PRs 1..N-1, and the
stack merges atomically through `merge-async`.

## Operating Context

- Runs in a tmux pane, about 110–150 columns by 30–45 rows. Mouse is on. Truecolor depends on tmux settings.
- Bumps come from `.github/workflows/update-deps.yml`, authored by `app/github-actions`, with titles prefixed `❄️ flake:` / `🤖 agents:` / `📌 pins:`. Most `flake.lock` bumps conflict with each other once one is merged.
- Auth reuses the `gh` login.

## Capabilities and Constraints

- Data comes from one GraphQL query: open PRs with `stack`/`stackEntry`, `statusCheckRollup`, `mergeable` and comments. It auto-refreshes; the interval is undecided (1–5 min).
- Stacked PRs merge only through `PUT /pulls/{n}/merge-async` plus polling. The synchronous merge endpoint and the `mergePullRequest` mutation don't work on them.
- Merging is allowed only in `DSestu/*` repos. It never uses `--admin` and never bypasses checks or branch protection.
- Images (kitty/sixel) are unavailable under tmux; the visuals rely on color, motion and mouse.
- Undecided: how conflicting bumps are handled after a merge, the refresh interval and the final name.

## Brand Commitments

None yet. The user asked for a "wow effect" and the most modern interaction a TUI can give.

## Evidence on Hand

- Real PR titles and authors: `gh pr list` in DSestu/NixConfig (e.g. #260 nixpkgs bump, #266 context-mode bump).
- Bubble Tea v2 feasibility demo: scratchpad `bt-demo`, which is throwaway.
- No users, metrics or testimonials; none are to be invented.

## Product Principles

1. Never merge by accident: one explicit confirmation per batch, and it shows exactly which PRs will land and which get skipped and why.
2. Stack truth over list truth: a PR that belongs to a stack is always shown and acted on as part of that stack.
3. Glanceable state: CI, conflict and mergeable status can be read from the list without opening a PR.
4. Keyboard first, mouse welcome: every action has a key; click, scroll and hover are extras.
5. Motion has a job: animation shows change (refresh, selection, merge progress) and is never decoration that slows the next keystroke.
