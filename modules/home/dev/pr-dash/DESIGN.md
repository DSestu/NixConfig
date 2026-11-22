---
name: pr-dash
description: Charm Glow PR dashboard for a tmux pane. Rail, table, preview, one merge bar.
colors:
  ground: "#16121f"
  text: "#e8e3f5"
  sub: "#a49dbb"
  dim: "#6e6585"
  border: "#3a3350"
  pink: "#ff5fd2"
  pink-dim: "#b9489c"
  violet: "#9d7cff"
  violet-dim: "#745cbc"
  mint: "#5fe3b0"
  mint-dim: "#49a484"
  coral: "#ff6b81"
  coral-dim: "#b95064"
  amber: "#ffcf5c"
  amber-dim: "#b9964a"
  cursor-row: "#2a2140"
  merge-bar: "#231c33"
  flash: "#4d2357"
typography:
  title:
    fontFamily: "terminal monospace (the user's)"
    fontWeight: 700
  body:
    fontFamily: "terminal monospace (the user's)"
    fontWeight: 400
  meta:
    fontFamily: "terminal monospace (the user's)"
    fontWeight: 400
    fontVariation: "italic"
rounded:
  box: "1 cell (╭ ╮ ╰ ╯)"
spacing:
  cell: "1 col"
  rail: "20 col"
  narrow: "110 col"
components:
  panel-focused-tab:
    backgroundColor: "{colors.violet}"
    textColor: "{colors.ground}"
  panel-tab:
    textColor: "{colors.sub}"
  chip-fail:
    backgroundColor: "{colors.coral}"
    textColor: "{colors.ground}"
    padding: "0 1 col"
  chip-warn:
    backgroundColor: "{colors.amber}"
    textColor: "{colors.ground}"
    padding: "0 1 col"
  row-cursor:
    backgroundColor: "{colors.cursor-row}"
    textColor: "{colors.text}"
  merge-bar:
    backgroundColor: "{colors.merge-bar}"
    textColor: "{colors.dim}"
    height: "1 row"
  dialog-confirm:
    backgroundColor: "{colors.pink}"
    textColor: "{colors.ground}"
---

# Design System: pr-dash

Ground truth is the shipped Go code under `internal/ui/`. Every colour lives in
`theme.go` and nowhere else; if a value here disagrees with `theme.go`, the code wins.

## Overview

**Creative North Star: "Charm Glow"**

A violet-black terminal lit by two neon voices, pink and violet, with three
status colours (mint, coral, amber) that only ever mean pass, fail and
running/marked. Panels are rounded Charm boxes; the focused one glows violet and
the rest sink into a dark border. Density is high (one PR per row, all state on
the row) but the ground stays quiet so the glow reads.

It is the approved comp pair `.impeccable/mocks/decision/surface/rail-three-col.html`
(layout) and `.impeccable/mocks/decision/theme/charm-glow.html` (look). It is
explicitly not gh-dash: no grey table on the terminal default background, no
emoji, no browser-tab section bar, no cursor glide.

**Key Characteristics:**
- One painted ground (`View().BackgroundColor = ground`), never the terminal default.
- Focus is colour, not position: violet border plus a violet filled title tab.
- State is a 1-cell glyph or a filled chip, readable without opening a PR.
- Motion only reports change: spinner while busy, a 15-frame fade on changed rows.

## Colors

A dark violet neutral ramp, two brand neons, and a three-colour status set, each
with a `-dim` twin for quieter contexts.

### Primary
- **Glow Pink** (pink): the action voice. Cursor bar `▌`, selected row number, key letters in the footer and dialog, the `fetching…` spinner, list bullets and headings in markdown, the confirm-dialog frame and its `y` chip.
- **Deep Pink** (pink-dim): PR numbers in the preview title and the dialog.

### Secondary
- **Charm Violet** (violet): focus. Focused panel border and title tab, table column headers, comment authors, link text (underlined), markdown H1 background and H3.
- **Muted Violet** (violet-dim): preview section rules (`Checks`, `Body`, `Comments`), the branch name in the header.

### Tertiary (status)
- **Pass Mint** (mint / mint-dim): `✓` checks, `N merged`, `N ready`. The dim twin is used in the preview and idle bar so green never shouts.
- **Fail Coral** (coral / coral-dim): `✗` checks, `failing` chip, the age of a failing PR, errors in the header, conflicts. Dim twin for the rail's Failing count.
- **Running Amber** (amber / amber-dim): `●` pending checks, the marked `●`, `conflict` and stack `n/m` chips, the flash notice, a near-limit rate counter.

### Neutral
- **Violet Night** (ground): the whole screen, and chip text.
- **Lavender Text** (text): titles and body copy.
- **Lilac Sub** (sub): secondary text, unfocused tab titles, unfocused markdown body.
- **Dusk Dim** (dim): metadata, hints, diff counts, ages, empty states.
- **Border Plum** (border): unfocused frames, `·` separators, horizontal rules, the scrim.
- **Cursor Plum** (cursor-row): background of the row under the cursor.
- **Bar Plum** (merge-bar): background of the one-line merge bar.
- **Flash Plum** (flash): first frame of the changed-row fade, blended down to ground.

### Named Rules
**The Status Means Status Rule.** Mint, coral and amber are never decorative. Mint is pass/ready/merged, coral is fail/conflict-error, amber is running/marked/needs-attention. A new state picks one of these by meaning or stays neutral.

**The One Palette File Rule.** Colours are declared once in `theme.go` (`c*` vars, `s*` styles, `glamourStyle`). No `lipgloss.Color("#…")` elsewhere.

**The Dim Twin Rule.** Inside the preview, rail counts and the idle merge bar, use the `-dim` twin; the full-strength colour is for the table row and the dialog, where the eye should land.

## Typography

**Font:** the user's terminal monospace. The app sets no face and no size.

**Character:** hierarchy comes from colour and three attributes only: bold, italic, dim colour. No underline except link text, no blink, no reverse.

### Hierarchy
- **Title** (bold): panel tabs, table headers (`sViolet.Bold`), selected row number and title, preview `#N title`, section rules, key letters, chips.
- **Body** (regular, text or sub): PR titles, markdown, check names.
- **Meta** (italic, dim): the `author opened 3d ago` line in the preview; glamour comments in code blocks.
- **Label** (regular, dim, padded `%-7s`): preview field labels `base`, `stack`, `diff`, `merge`, `draft`.

### Glyph set (all 1 cell wide)
`✓` pass · `✗` fail · `●` running/marked · `○` unmarked · `·` no checks and separator · `├ └` stack rows · `▌` cursor · `◆` the app pill · `↻` refresh countdown · `→ ←` merge direction · `‹ ›` collapsed section title · `⇢` enqueued · braille spinner `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` · `…` truncation · `−` (U+2212) in diff counts.

Title emoji map to glyphs in `model.Glyph`: `❄→*`, `🤖→◆`, `📌→▲`, `✨→✦`, `🌐→◎`.

### Named Rules
**The One Cell Rule.** Every glyph is exactly one cell, so columns never shift. Emoji in a title prefix are mapped; new prefixes get a 1-cell glyph in `model.Glyph`, never a raw emoji.

## Layout

Fixed vertical stack, painted to the full terminal (`view.go`):

1. Header line (1 row).
2. Box row: rail | table | preview, height `h − 3`.
3. Merge bar (1 row).
4. Footer of key hints (1 row).

**Columns** (`layout()`): at ≥ 110 cols the rail is 20 cols; the remaining width
splits table 72 : preview 58 (`rest*58/130`). Below 110 cols the rail is hidden,
the table takes 55 % and the preview 45 %, and the table title becomes
`‹ Section N ›`; `[` `]` switch sections and `tab` skips the hidden rail
(`motion_test.go` `TestNarrowLayout`). Every line is exactly `w` cells wide (`fit`).

**Table row anatomy** (`row()`, fixed edges `leftW 11`, `rightW 17`):
cursor `▌`(1) · mark `○/●`(3) · sp · `#num` right-aligned(5) · sp · title (flex, with
`├ `/`└ ` stack prefix and an optional trailing chip) · sp · check glyph(1) · sp ·
`+a −d`(9) · sp · age(3) · sp. Columns header: `mk # title ck ± age` in bold violet.
Last body line of the table is a dim summary: `N PRs · N marked · newest first, stacks grouped`.

**Preview** (`preview.go`): one cell padding each side; title, italic meta, blank,
label block, then rule-headed sections Checks n/m, Body, Comments n.

**Spacing.** The unit is one cell. Separators are ` · ` in Border Plum. No blank
padding rows inside the table.

## Elevation & Depth

Flat. There are no shadows; depth is two moves only.

- **Focus lift**: the focused panel's border turns violet and its tab fills violet; the others stay Border Plum with a Lilac Sub tab.
- **Modal scrim**: when the merge dialog is open, the whole screen behind it is stripped of styles and redrawn in Border Plum (`scrim()`), then the dialog is overlaid centred.

**The Flat Scrim Rule.** A modal never sits on live colour. Everything behind it flattens to one dark tone so only the dialog reads.

## Shapes

Rounded box-drawing frames (`╭─ title ─╮ │ ╰─╯`) with the title as a tab cut into
the top edge (`frame()`). Internal dividers are `├──┤` (`sepLine`, used once, above
Marked in the rail). Chips are rectangles of one padded space either side. The
header pill ` ◆ pr-dash ` is a per-cell gradient from pink to violet (`pillStops`).

## Components

### Panel box
- **Shape:** rounded frame, title tab ` Title ` after `╭─`.
- **Focused:** violet border, tab is a violet chip (ground text, bold).
- **Unfocused:** Border Plum border, tab in bold Lilac Sub.

### Chips
- **Style:** ground-coloured bold text on a filled status colour, ` label `.
- **Variants:** `failing` and failed skips on coral; `conflict`, stack `n/m`, `N marked` and other skips on amber; `draft` is plain dim text with no fill. The dialog's go button is a pink chip.
- **Rule:** at most one chip per row; precedence failing > conflict > stack > draft.

### Table row
- **Default:** title in text, number in sub, meta in dim.
- **Cursor:** whole row on Cursor Plum, pink `▌` in the first cell, bold pink number, bold title.
- **Marked:** amber `●` in the mark column; unmarked is dim `○`.
- **Changed:** background fades Flash Plum → ground over 15 frames.

### Section rail
Eight sections with right-aligned counts: All, Mine, Bumps, Stacks, Review,
Failing, Conflicts, a `├──┤` divider, then Marked. Current section: pink `▌`,
bold text name. Non-zero Failing count in coral-dim, Conflicts in amber-dim,
Marked name and count in amber-dim.

### Preview sections
Section rule = bold violet-dim title + Border Plum `─` to the edge. Check lines:
bold glyph (mint-dim / coral / amber-dim), name in sub, duration or `running` in dim.
Markdown via glamour with `glamourStyle()`: no margins, no `##` markers, pink headings
and bullets, H1 as a violet chip, pink inline code on Cursor Plum. Links show
only their text as an OSC 8 hyperlink; bare URLs get short labels
(`owner/repo#12`, `owner/repo@abc1234`; `markdown.go`). An unfocused preview
renders body text in sub.

### Merge confirm dialog (`merge.go`)
- **Frame:** pink border, pink chip tab `Squash-merge N PRs into owner/repo` (prefixed `Dry run:` in dry-run); width `min(84, w−4)`, centred over the scrim.
- **Vocabulary:** `Lands, in this order:` then numbered steps `1.`; each step shows `#N title`, a check summary (`✓ 3/3 checks`, or amber-dim `no checks` spelled out), `· → base`, and `stack: lands #a #b together` for stacks. `Skipped:` lists coral `✗ #N reason · title`.
- **Progress:** status cell is 3 wide: `1.` → amber spinner `merging…` → mint `✓` / mint `⇢ added to the merge queue` / coral `✗ message`.
- **Footer:** pink chip `y  squash-merge N PRs` · `n cancel`; while running `merging i/n…` plus the ctrl+c caveat; done shows `N merged · N failed · enter close and refresh`.

### Merge bar
One row on Bar Plum. Idle: `nothing marked ·` then health `N ready` (mint-dim) ·
`N failing` (coral) · `N conflicting` (amber). With marks: amber chip `N marked` →
bold pink `M` `squash-merge N in order`, then skip chips. A flash notice replaces
the whole bar in amber until the next key.

### Header and footer
Header: gradient pill, dim repo, violet-dim branch, then ` · `-separated status:
pink spinner `fetching…` or dim `↻ 42s`, `updated 15:04:05`, `rate r/l` (amber
under 10 %), coral `✗ error`. Footer: bold pink key, dim action, ` · ` separators.

## Interaction

- **Keys** (`model.go`): `tab`/`shift+tab` panel, `[` `]` section, `j/k`/arrows move, `pgup/pgdown`/`ctrl+u/d` page, `space` mark (stack-aware), `a` mark all / toggle off, `m` merge cursor PR, `M` merge marked, `enter` open in browser, `r` refresh, `q` quit. In the dialog: `y`, `n`/`esc`/`q`, `enter` to close the summary.
- **Mouse:** left click focuses the panel under the pointer and selects the rail section or table row; a click in the first 5 cols of a row toggles its mark. Wheel scrolls the panel under the pointer (3 rows, one section per notch in the rail) without moving focus. No hover effects. Mouse is ignored while the dialog is open.

## Motion

- One frame ticker at 80 ms (`frameEvery`), armed only while something is busy (fetching, merging, a row fading) and stopped otherwise.
- Braille spinner for fetch and the merging step.
- Changed-row fade: 15 frames (~1.2 s) from Flash Plum to ground, for PRs that are new or whose head, check rollup, comment count or mergeable changed. Never on first load; `UNKNOWN` mergeable settling is not a change (`TestChangedRowsFade`).
- **The No Glide Rule.** The cursor jumps; it never animates between rows. Motion must never delay the next keystroke.

## Do's and Don'ts

### Do:
- **Do** paint every cell: pad with `fit`/`bar` so each line is exactly the terminal width on the ground colour.
- **Do** take colours only from `theme.go` and pick status colour by meaning.
- **Do** keep focus visible as the violet frame plus filled violet tab.
- **Do** spell out risk in the dialog (`no checks`, skip reasons, stack groupings).
- **Do** keep every glyph one cell and map new title emoji in `model.Glyph`.
- **Do** cache glamour output (`mdCache`); rendering is too slow per frame.

### Don't:
- **Don't** leave the terminal default background or use grey ANSI 16 colours; that is gh-dash.
- **Don't** show raw emoji, raw URLs or footnote link lists in titles or the preview.
- **Don't** add cursor glide, spring easing or decorative animation.
- **Don't** add a second accent colour or use mint/coral/amber decoratively.
- **Don't** draw a modal over unflattened colour; always scrim.
- **Don't** add hover effects; click and wheel only.
