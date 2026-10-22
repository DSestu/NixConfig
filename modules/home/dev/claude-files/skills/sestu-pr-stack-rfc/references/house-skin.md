# House diagram skin

A green-on-slate palette, contrast-checked on its paper color. Use these values directly; they replace the diagram-design skill's default style guide, so skip its first-run style gate.

## Colors

| Role | Hex | Use |
|---|---|---|
| paper | `#f7f9fa` | Page and SVG background, node masks, label masks |
| paper-2 | `#ebeef0` | Rare secondary fill |
| ink | `#2a3540` | Text, NEW node stroke. As rgba: `rgba(42,53,64,X)` |
| muted | `#52667a` | Sublabels, default arrows, legend text |
| soft | `#677279` | Zone labels, PR numbers, muted arrow labels |
| rule-solid | `#c9d0d6` | Hairlines when needed |
| accent | `#2a8013` | Focal nodes only (1 to 2 per diagram), 4.74:1 on paper |
| accent-tint | `rgba(42,128,19,0.08)` | Focal node fill; `0.20` for focal chips |
| link | `#203a9a` | External API calls |

Lighter brand greens (around `#69c028`) fall near 2:1 on paper: never use them for text or strokes.

Data-type chips in data-flow diagrams keep the diagram-design colors: WB `#6e6479` (API payload), DB `#5e7a9b` (raw file), TB `#b8915a` (DWH table), FL `#9c6b50` (file/report), LS `#4a7c59` (stream).

## Fonts

```html
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&amp;family=Mulish:wght@400;600;700&amp;family=Geist+Mono:wght@400;500;600;700&amp;display=swap" rel="stylesheet">
```

- Title (h1): Instrument Serif 400, for contrast with the sans body.
- Node names: Mulish 700 (`--sans`).
- Sublabels, tags, arrow labels, file/table/function names: Geist Mono.

## CSS variables block

```css
:root {
  --paper: #f7f9fa; --paper-2: #ebeef0; --ink: #2a3540; --muted: #52667a;
  --soft: #677279; --rule: rgba(42,53,64,0.12); --accent: #2a8013;
  --accent-tint: rgba(42,128,19,0.08); --link: #203a9a;
  --sans: 'Mulish', system-ui, sans-serif; --serif: 'Instrument Serif', serif;
  --mono: 'Geist Mono', ui-monospace, monospace;
}
```

## Change-status treatments (impact diagrams)

| Status | Fill | Stroke | Tag text color |
|---|---|---|---|
| NEW | `#ffffff` | `#2a3540` 1px | ink |
| CHANGED shared code (focal) | `rgba(42,128,19,0.08)` | `#2a8013` 1.2px | accent |
| CHANGED, not shared | `#ffffff` | `#52667a` 1px | muted |
| EXISTING / READ ONLY | `rgba(42,53,64,0.02)` | `rgba(42,53,64,0.20)` dashed `4,3` | muted |
| EXTERNAL | `rgba(42,53,64,0.03)` | `rgba(42,53,64,0.30)` | muted |
| DELETED | `rgba(42,53,64,0.02)` | `rgba(42,53,64,0.30)` dashed `2,2`; name struck through | muted |
