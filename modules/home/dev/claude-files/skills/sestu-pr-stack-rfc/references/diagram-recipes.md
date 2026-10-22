# Diagram recipes

Three diagrams, in the house skin (`house-skin.md`). Geometry rules come from the diagram-design skill. Find its install with:

```bash
DD=$(ls -d ~/.claude/plugins/cache/diagram-design/diagram-design/*/skills/diagram-design | sort -V | tail -1)
```

Read `$DD/references/primitives-core.md` (the six connector rules, node box, labels, accessible SVG) before drawing anything, plus the type reference named in each recipe. Those rules are not negotiable: orthogonal `r=8` elbows, a 6 to 10px gap between label masks and strokes, no overlapping strokes, fanned attach points, no line passing behind a box that isn't an endpoint, arrows drawn before boxes, 4px grid.

## Contents
1. Code/DB impact (always)
2. Data flow (when data moves between systems)
3. DB schema (when migrations create or alter tables)
4. Shared page scaffold and checks

## 1. Code/DB impact

**Question it answers:** what does this stack add or change in Airflow and the DWH, and what existing code is affected? Readers are the colleagues who will review the PRs.

**Type:** architecture (`$DD/references/type-architecture.md`). Start from `assets/example-impact.html` and replace the content; keep its CSS, tag, PR-number and legend patterns.

**Nodes (9 max).** Each node is a unit a reviewer reasons about, not a file: a DAG plus its SQL, a shared operator, a schema, an external system. Merge files that always change together. Each node carries:
- a status tag (NEW, CHANGED, EXISTING, READ ONLY, EXTERNAL, DELETED) styled per `house-skin.md`;
- the PR number(s), right-aligned in the header row (`#102`, or `#101 · #102`);
- a name in Mulish and two mono sublabels with real identifiers: files, tables with their key, function signatures with the new parameter (`push_batch(conn_id)`), schedules.

**Accent (1 to 2 nodes):** the CHANGED pieces of shared code, because that's where a reviewer has to check unchanged callers. If nothing shared changes, accent the riskiest new piece (the one writing to production or to an external system). Never accent more than two.

**Show the blast radius.** For each CHANGED shared node, search the repo for its other callers (`rg -l 'push_batch\(' dags/`). If callers exist that the stack doesn't touch, add one EXISTING node for them ("Existing DAGs") with dashed "also calls this code" arrows and a sublabel saying whether their behavior changes ("same defaults: raw · crm_default"). This is usually the most useful node in the diagram.

**Zones (3 max):** by runtime, e.g. `AIRFLOW · PRODUCTION ONLY`, `DWH`, with external systems outside any zone. Put environment gating in the zone label when the code has it (`if Variable.get("environment") == "production"`).

**Arrows:** data direction, muted. Link-blue for calls to an external API. Dashed for "also calls this code". Labels only where the verb isn't obvious (READ, UPSERT, DIFFS, WRITE), 14 characters max.

**Layout that worked:** external system on the left, spanning the rows; zone 1 with the load path on the top row (left to right) and the write-back path on the bottom row (right to left); the existing-callers node between the two shared nodes in the same column, so its dashed arrows are straight vertical lines; DWH zone on the right. viewBox 960 wide.

## 2. Data flow

**Question it answers:** how does the data move end to end, and in which order?

**Type:** data flow (`$DD/references/type-data-flow.md`, parametric: follow its §2 formulas exactly). Start from `assets/example-data-flow.html`.

- Lanes (4 max) are places the data lives or runs: the external system, Airflow, each DWH schema.
- Steps (6 max) are verbs: LOAD, STORE, MATCH, GUARD, PUSH.
- Exactly one focal step, one focal node, one focal labelled arrow (the hand-off that matters, e.g. DIFFS into the guards).
- Put status and PR numbers in the tool line (`loader.conf · #102`), and real numbers in sublabels (`120,000 EU contacts`).
- Node titles at 9px Mulish 700 have about 17 characters in a 100px box. Shorten names rather than shrinking text.

## 3. DB schema

**Question it answers:** which tables and columns do the migrations create or alter, with which keys?

**Type:** database schema (`$DD/references/type-db-schema.md`). No example asset: build from that reference.

- Only tables touched by the stack, plus the existing tables they join or reference (5 tables max, 8 columns shown each, `+ N more columns` for the rest).
- Columns with real SQL types from the migration, PK/FK/UQ/NN chips, and the composite key spelled out (`PRIMARY KEY (region, id)`).
- Group by schema (`partner`, `core`) with the dashed schema rect.
- **Accent, adapted for PR review:** the generic rule accents a destructive FK. Here, accent the header band of the new or altered tables (2 max), since that's what the reviewer is checking. Keep a CASCADE FK accented if one exists, and then accent only one table.
- Tag each table with the migration file (`V42`) and PR number in its header.
- Skip this diagram when the stack has no DDL, or only one trivial table that the impact diagram already describes. A schema diagram with one box isn't worth drawing.

## 4. Shared page scaffold and checks

- One HTML file per diagram, named `<slug>.html` in the output folder. `<title>` first in the SVG, `role="img"`, `aria-labelledby="<slug>-title <slug>-desc"`, a one-sentence `<desc>` about content.
- Wrap the SVG in `<div class="scroll">` with `overflow-x: auto`, and set `svg { min-width: <viewBox width>px }`.
- Eyebrow (`Architecture · <project>, PRs #A to #D`) and an Instrument Serif h1 that states the subject plainly.
- Before rendering, check text fit by budget: mono 0.62em per character, sans 0.60em. A 9px mono sublabel in a 176px node fits about 28 characters.
- Run `python3 $DD/scripts/self_check.py <file>`; it must print `OK`.
- Render: `python3 <skill-dir>/scripts/render_png.py <file>.html` (writes `<file>.png`, cropped to the viewBox, 2x).
- Look at the PNG with the Read tool. Fix clipped text, labels touching lines, arrows through boxes, legends cut off. Re-render until it's clean.
