# Core Rules

## Investigation & Accuracy
- Never speculate about code you have not read. Read files and ripgrep for usages before making claims
- If the user references a file, read it before answering
- If uncertain, say so and propose how to verify. Do not fabricate APIs, paths, or behavior

## Scope Discipline
- Do what has been asked; nothing more, nothing less
- When intent is ambiguous, default to research and recommendations — only edit when explicitly asked
- Make only the changes requested. Do not refactor adjacent code, add docstrings to unchanged code, or create abstractions for a single use
- Follow scoping words ("only", "just", "exactly") literally

## Verification & Safety
- Before declaring done: re-check requirements, run tests and lint, state what changed and what you could not verify
- Ask before destructive actions: deleting files/branches, force pushes, hard resets, --no-verify
- Edit existing files in place. Do not create new files unless required. Clean up scratch files

## Efficiency
- Parallelize independent tool calls; serialize dependent ones
- Never use placeholder or guessed parameters

## Memory Resilience
- When updating CLAUDE-*.md memory bank files, also sync key content to native auto memory topic files
- Maintain memory/MEMORY.md as an index of memory bank files and their current state
- After learning behavioral preferences from corrections, save them as auto memory entries
- If CLAUDE.md is reset or wiped, check auto memory via `/memory` to recover project context

## Git

- NEVER commit without explicit user consent. Stage changes and show the diff, then wait for the user to say "commit". A prior commit instruction does not authorise subsequent commits.
- "commit" means the full flow: create a branch, commit, push, open a PR (title only, `--body ""`), wait for the GitHub Actions checks, then squash-merge. Push and open the PR in the foreground, then run the CI wait and merge as one background Bash command (`gh pr checks <n> --watch --fail-fast && gh pr merge <n> --squash`), not a subagent: an agent took up to 10 minutes per PR. If the repo has no checks, merge right away. If checks fail, don't merge; report the failure.
- NEVER use `git reset --soft origin/master` to squash a branch that is behind master. It silently reverts other people's merged work. Always `git rebase origin/master` FIRST.
- Preferred squash: `git fetch origin master && git rebase -i origin/master` (pick first, squash rest)
- Before any squash, verify with `git log origin/master..HEAD` that only your commits appear
- Never write a description in a PR you open. Title only — the commit messages carry the rationale, and a PR body just duplicates them and rots. Use `gh pr create --body ""`, and clear the body `gh stack submit --auto` copies from the commit

## Knowledge Repo

- When a command or approach is corrected during a conversation, immediately update the relevant doc in `/home/david/github/knowledge` — do not wait to be asked
