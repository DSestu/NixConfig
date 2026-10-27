---
name: sestu-pr-stack-rfc
description: Turn a set or stack of GitHub PRs into a house RFC-style design document (Problem, Key considerations, Solution, Impact, Plan with PR links) with rendered diagrams in a consistent brand palette that show the code and DB impact, the data flow, and the schema changes. Publishes to Notion (rewriting a ticket or creating an RFC page, with PNG diagrams uploaded), to local markdown, or as GitHub PR descriptions with a styled mermaid impact diagram and the stack position on every PR. Use this whenever the user wants to document, explain, or write up PRs, a PR stack, a gh-stack, or a branch for reviewers, a Notion ticket, or the PR descriptions themselves, wants "a diagram of what my PRs change", wants a ticket description rewritten from its PRs, or mentions an RFC for work that is already coded, even if they don't say "RFC" or "skill".
---

# PR stack → RFC document

Produce what a reviewer needs to understand a stack of PRs in one read: a document in the house RFC style, plus diagrams that show at a glance what is new, what shared code changes, and which tables move. The reader is a colleague about to review the PRs, so everything serves that review: real file, table and function names, PR numbers on every component, and honesty about what isn't tested.

## Inputs

- PRs: numbers, URLs, a gh-stack, or a branch range (`git log origin/master..HEAD`). If the user gives none, use the current branch's stack (`gh pr list --author @me --state open`, or `gh stack view` if gh-stack is installed) and confirm the list.
- Optional: a Notion ticket or page URL, a sample RFC to imitate, or facts that aren't in the code (row counts, status of external dependencies).

## Workflow

### 1. Collect the facts

Run from inside the repo:

```bash
<skill-dir>/scripts/collect_prs.sh /tmp/pr-rfc/<slug>/prs <pr>...
```

It writes each PR's JSON, its full diff, and a `summary.txt` (files, commits, bodies). Read the diffs themselves, since they are the source of truth; commit messages give the rationale. For each change, note:

- **Status per unit:** NEW, CHANGED, DELETED, and for CHANGED code whether it's shared (does code outside the stack call it?). Check with `rg` for callers. A changed default or signature in shared code is the most important thing to surface.
- **DB:** migrations (Flyway `V<n>__*.sql`, DDL), Terraform grants/schemas, new tables with their keys, columns read by new queries.
- **Runtime:** DAG ids, schedules, pools, connections/secrets, environment gating (`Variable.get("environment")`), dry-run flags, guards, failure thresholds.
- **External systems:** what is read and what is written, and where.

When a database MCP is available (tools named like `execute_sql_<db>_<env>`), run read-only queries to check what the code implies: whether a migration has been applied (`flyway_schema_history`), row counts of new tables, NULL rates of columns the code reads, grants. These numbers often hold the most useful finding of the document. Only SELECT and catalog queries; never write. Date every number in the text ("on 2026-01-15, 52,300 rows") and say which environment it comes from.

If a Notion page was given, fetch it too and keep the facts it holds that the code can't give (counts, IDs, who waits on what). If the page and the code disagree, trust the code and tell the user.

### 2. Ask where the document goes

Ask each time, with one multi-select question offering: (a) rewrite an existing Notion page (which one), (b) create a page in the team's RFC database (find it with `notion-search` for "RFC" and fetch it for its `collection://` URL and properties; status DRAFT), (c) a local folder only, (d) the GitHub PR descriptions. (d) combines with any of the others. If the user's request already says where ("document my PRs" means (d)), don't ask. Rewriting a page replaces its content, so name the page in the question.

For (d) only, skip steps 4 and 5 and follow `references/pr-body.md`: one body per PR with its own mermaid impact diagram, review focus and stack position. The user normally keeps PRs title-only; this mode is the exception they asked for, so write bodies only when (d) is chosen.

### 3. Plan the diagrams

- **Code/DB impact:** always.
- **Data flow:** when data crosses systems (load, sync, push, pipeline).
- **DB schema:** when migrations create or alter tables beyond something the impact diagram already says.

Tell the user in one or two lines which diagrams you'll draw and what you'll leave out to stay under the complexity budgets, then go ahead unless they redirect.

### 4. Draw

Read `references/diagram-recipes.md`, `references/house-skin.md`, and the diagram-design references it points to. Start from `assets/example-impact.html` and `assets/example-data-flow.html`; they are finished diagrams for a fictional partner-CRM stack, so copy their structure and replace every label. Then for each diagram:

1. Write `/tmp/pr-rfc/<slug>/<diagram>.html`.
2. `python3 $DD/scripts/self_check.py <file>` must print OK.
3. `python3 <skill-dir>/scripts/render_png.py <file>` writes the PNG.
4. Look at the PNG and fix what's wrong. Clipped text and arrows crossing boxes are the usual problems.

### 5. Write the document

Follow `references/rfc-style.md`: green numbered sections, a status callout, constraints, out of scope, key considerations, one Solution subsection per part of the design, alternatives only when they come from the sources, impact per team with untested parts named, and a Plan checklist where each code step carries its PR link. Put the impact diagram at the top of "3. Solution", the data flow where it explains the current or target flow, and the schema under "Data model".

Write plainly: no em dashes, no staged contrasts, sentence-case headings, every number sourced. If the `humanizer` skill is installed, run its rules over the text in embedded mode. Don't add facts the sources don't contain. A missing fact becomes a question in "Open questions" or a question to the user.

### 6. Publish

**Notion:**
1. For each PNG: call `notion-create-file-upload` with the filename, then
   `python3 <skill-dir>/scripts/notion_upload.py "<upload_url>" '<upload_headers JSON>' <png>`.
   Use its `markdown_source` as `<image source="file-upload://…" />` in the content. Uploads expire if not placed, so publish right after.
2. Before writing, read `notion://docs/notion-flavored-markdown-spec` if you haven't this session. Write `<`/`>` inside `<code>` as-is: code is literal in Notion, and `&lt;`/`&gt;` show up verbatim. Escape them only in plain text.
3. Rewrite: `notion-update-page` with `replace_content`. New page: `notion-create-pages` under the RFCs data source, with `Name`, `status: DRAFT`, `Impacted Components` if one fits, `Owner` as the user.
4. Fetch the page again and check headings, images and checklist links rendered. Fix anything that didn't.
5. If the page has a `GitHub PRs` property, make sure every PR of the stack is in it.

**GitHub PR descriptions:** follow the Publishing section of `references/pr-body.md`: write each body to a file, show them to the user, and post with `gh pr edit` only after they agree. When a Notion doc was also made, link it at the end of each body.

**Local:** write `/tmp/pr-rfc/<slug>/<slug>.md` with the images referenced by relative path, next to the HTML and PNG files.

### 7. Report

Tell the user where the document is (link or path), which diagrams were made with their file paths, what you left out of the diagrams, which facts you couldn't verify, and any disagreement between the ticket and the code. Show one PNG inline with `![…](path)`.

## Files

- `scripts/collect_prs.sh`: PR JSON, diffs and summary into one folder.
- `scripts/render_png.py`: diagram HTML to a PNG cropped to the SVG viewBox (headless Chromium + Pillow).
- `scripts/notion_upload.py`: sends a file to the URL returned by `notion-create-file-upload`.
- `references/rfc-style.md`: the RFC skeleton, voice and Notion markup.
- `references/house-skin.md`: palette, fonts, change-status node styles.
- `references/pr-body.md`: PR description template, house mermaid styles, posting with `gh pr edit`.
- `references/diagram-recipes.md`: how to build the impact, data-flow and schema diagrams.
- `assets/example-impact.html`, `assets/example-data-flow.html`: reference diagrams for a fictional partner-CRM stack.
