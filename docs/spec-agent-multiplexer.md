# Spec — parallel coding-agent multiplexer (working name: `wt`)

Status: **DRAFT v0** — nothing agreed yet. Every `?` marker is an open
question for the iteration pass (§10). Written to be cut down, not filled in.
Scope (proposed): `modules/dual/` for the command, `modules/home/dev/claude-code.nix`
for the status hooks. Fish + tmux + git worktrees, no daemon, unprivileged.

Context: this spec exists because `dmux` (npm, packaged at
`modules/home/dev/dmux/`) does the job but costs a patch per version bump
(`fish-pane-bootstrap.patch`), guesses agent state with an LLM, and fights
tmux over window sizing. The bet is that a fish-native tool with **~200 lines
of logic** covers the parts actually used, because hooks give us for free the
one signal dmux works hardest to obtain.

## 1. Objective

Run several coding agents in parallel on the same repo, each isolated in its
own git worktree, and always know at a glance **which one is waiting for me**.

Target user: the repo owner, on the Kali workstation (primary) and NixOS
hosts (secondary). Single user, single machine, one agent CLI (Claude Code).

Success is a Saturday's build that never needs patching upstream — not
feature parity with dmux.

## 2. The three things it must get right

Everything else in this document is negotiable. These are the reasons to
build it at all:

1. **State comes from hooks, never from the screen.** Claude Code fires
   `Stop`, `Notification`, `UserPromptSubmit`. A hook writes one word to a
   state file. No LLM call, no polling, no OpenRouter key, no
   misclassification. (dmux's `PaneAnalyzer` needs an API key and reports
   every pane as "working" without one.)
2. **Never type shell syntax into an interactive shell.** The agent is the
   window's command (`tmux new-window <agent> <prompt>`), not a string typed
   into fish via `send-keys`. This class of bug — dmux emitting
   `VAR=$?; if [ ... ]; then` into a fish prompt — becomes structurally
   impossible.
3. **Never take ownership of tmux sizing.** Leave `window-size` at `latest`.
   dmux sets it to `manual` and recomputes dimensions itself, which is how a
   196-column terminal ends up with a 120-column window.

## 3. Model

| Concept | Realised as |
|---------|-------------|
| a task | a git worktree + a branch, both named `<slug>` |
| a running agent | one tmux **window**? (not a pane in a split layout) |
| the overview | the tmux **status line**? (not a sidebar TUI) |
| agent state | one file per task, written by a hook |

Using windows instead of a split layout is what removes the layout problem:
tmux already handles window sizing, and the window list is already an
overview. Cost: no side-by-side view of two agents. **?** — this is the
biggest open question in the spec (§10.2).

Worktrees live at `<repo>/.wt/<slug>`? Branch is `<slug>`, no prefix?

## 4. Command surface (proposed, to be cut)

```
wt new <slug> [prompt ...]   create worktree + branch, open window, launch agent
wt ls                        list tasks: slug, state, branch ahead/behind, dirty
wt j [slug]                  jump to a task's window (no arg → fzf picker)
wt rm <slug>                 kill window, remove worktree, delete branch
wt merge <slug>              merge branch into the base branch, then rm
```

Five verbs. Anything beyond this is a §9 non-goal until argued for.

Naming: `wt new fix-auth "fix the JWT expiry bug"` → worktree `.wt/fix-auth`,
branch `fix-auth`, window named `fix-auth`, agent launched with the prompt as
its initial instruction. No AI-generated slugs; you type the name.

**?** Is `wt merge` in scope for v1, or is merging a thing you'd rather do by
hand in the main worktree?

## 5. State via hooks (the load-bearing part)

A hook script writes a single word to
`$XDG_RUNTIME_DIR/wt/<slug>.state`. Proposed mapping:

| Claude Code hook | State written | Meaning |
|------------------|---------------|---------|
| `UserPromptSubmit` | `working` | agent has been given something to do |
| `PreToolUse` | `working` | still going |
| `Notification` | `waiting` | needs you — permission or a question |
| `Stop` | `done` | turn finished, no one is blocked |

`wt ls` and the tmux status line read those files. Nothing polls pane
content; nothing calls an API.

Wiring: the hooks go into `settings.hooks` in
`modules/home/dev/claude-code.nix`, alongside the existing i-have-adhd
SessionStart hook. The slug comes from the worktree directory name, so the
hook is one line of fish and needs no per-task configuration.

**?** Does Cursor need parity here (CLAUDE.md rule)? Cursor runs no hooks, so
a Cursor-launched agent would show no state at all. Options: accept
Claude-only and state so, or fall back to a coarse "process alive" check for
non-hook agents.

## 6. Visual indicators

Reuse the Tide/dmux vocabulary already in your muscle memory:

| Glyph | State | Where |
|-------|-------|-------|
| `✻` | working | tmux status line, per window |
| `△` | waiting on you | status line, plus window name flagged |
| `◌` | done / idle | status line |

**?** Is a coloured window-name flag enough, or do you want the count of
waiting agents somewhere always-visible (Tide right prompt, status-right)?

## 7. Project structure (proposed)

```
modules/dual/wt/
  wt.nix              the command (fish function or writeFishApplication)
  wt.fish             logic, if it grows past inline-in-nix size
modules/home/dev/claude-code.nix   + hooks writing state files
docs/spec-agent-multiplexer.md     this file
```

`modules/dual/` because it should work on Kali (home-manager) and the NixOS
hosts from the same source, like `ns` does.

## 8. Verification

- `wt new` on a scratch repo creates exactly one worktree, one branch, one
  window; `git worktree list` shows it. (The dmux failure mode was writing
  config for worktrees it never created — the check is always on disk, never
  in a config file.)
- State transitions observable: launch a task, see `working`; let it ask a
  question, see `waiting`; let it finish, see `done`.
- `wt rm` leaves `git worktree list` and `git branch` exactly as they were
  before `wt new`.
- Resize the terminal with several tasks open: every window still fills it.
- Nix builds go through a subagent, per CLAUDE.md.

## 9. Non-goals (deliberately excluded — argue one back if you want it)

Each of these is a dmux feature examined and dropped:

| Excluded | Why |
|----------|-----|
| Autopilot (auto-answering prompts) | needs an LLM in the loop; "always press option 1" is not a safety model |
| LLM branch names / commit messages | you can type a slug faster than it can guess one |
| Sidebar TUI | the tmux window list already is one; a TUI is what forces manual sizing |
| Web dashboard / HTTP API | no |
| Multi-agent registry (12 CLIs) | you use one; per-agent send-keys delays are pure tax |
| Goal mode | prefixes `/goal`, which does not exist in your Claude Code |
| Multi-project in one view | one repo at a time; a second terminal is free |
| Desktop notifications | **?** possibly the one worth keeping — see §10.5 |
| Lifecycle hooks (`worktree_created`, …) | `direnv` + `devenv` already cover per-worktree setup |

## 10. Open questions to settle in the iteration pass

1. **Name.** `wt`? Something else? It must not collide with anything on
   `PATH` in a `ns` shell.
2. **Windows or panes?** (§3) Windows are free and unbreakable; panes let you
   watch two agents at once. Pick one — this decides half the code.
3. **Merge in scope?** (§4) Or does `wt` stop at "worktree exists, branch
   exists, you take it from there"?
4. **Where do worktrees live?** `<repo>/.wt/` (visible, needs gitignore) vs
   `~/.cache/wt/<repo>/<slug>` (invisible, breaks relative paths in tooling).
5. **Notifications?** The one dmux feature that might earn its place: a
   `notify-send` when an agent goes `waiting` while you're in another window.
6. **Replace dmux or coexist?** If `wt` lands, does
   `modules/home/dev/dmux/` get removed (and its patch retired), or stay as
   the heavyweight option?
7. **Does the spec need a v1 cut line?** i.e. is §4's five-verb surface
   already too big for a first landing.

## 11. Explicitly not decided yet

Nothing in §3-§7 is agreed. This draft exists to be argued with; the
next pass should end with §10 empty and a `Status: APPROVED` line at the top.
