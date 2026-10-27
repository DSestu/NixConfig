# RFC style

The house RFC format: five numbered green sections in Notion, plain prose, sourced numbers. If the user points at a template page or sample RFCs, read them first and let them override anything here.

## Contents
1. Skeleton
2. Section by section
3. Tables, code, diagrams
4. Voice
5. Notion markup to copy
6. Worked example (fictional)

## 1. Skeleton

Default to the green, numbered variant:

```
<callout icon="💡" color="gray_bg">
Status: <one line on where things stand>. Code: stack [#A](url) → [#D](url) (<draft/open>), <deployed or not>.
</callout>

# <span color="green">1. Problem / Motivations</span>
## Current behavior            (optional, when there is an existing system)
## Constraints we found        (or "Problems"; numbered list with a bold lead, or one ### per issue)
## Out of scope
# <span color="green">2. Key considerations</span>
# <span color="green">3. Solution</span>        ("Possible Solutions" when options are still open)
## <one ## per part of the design: Data model, Load, Push, ...>
## Alternatives considered
# <span color="green">4. Assessment of impact</span>
# <span color="green">5. Plan</span>            ("Decision" + "Next Steps" for a classic RFC)
## Steps
## Open questions
```

Drop any section with nothing true to put in it. A pink, unnumbered variant (`# <span color="pink">…</span>`, preceded by `<table-of-contents color="gray" />`) also exists; use it only if the user asks or the page already uses it.

When the PRs are already written, the document describes a chosen design, so "3. Solution" replaces "3. Possible Solutions", and "5. Plan" replaces "5. Decision". Keep "Possible Solutions" with Pros/Cons (a `| Pros | Cons |` table per option, plus an "Effort: … Risk: …" line) and a GO/NO-GO decision when the user is still choosing.

## 2. Section by section

- **Problem / Motivations.** What the business or the system needs, in two or three sentences, then the facts that shape the design. Put measured numbers here (row counts, latencies, volumes) and say where they come from.
- **Constraints we found.** Facts discovered while building that a reviewer would not guess: ID spaces that collide, missing sandboxes, sizes, risky failure modes. Bullet list.
- **Out of scope.** Short bullets. Things a reader might expect the PRs to do and that they don't.
- **Key considerations.** The requirements the solution must respect, as plain bullets ("No push can reach the partner from preprod"). Four to six is typical; group them under `####` sub-headings when there are many.
- **Solution.** One `##` per part of the design. Each part says what exists after the PRs, with file, table, DAG and function names in `<code>`. The impact diagram goes at the top of this section; the data-flow diagram goes in Problem/Current behavior (current state) or here (target state); the DB-schema diagram goes under "Data model".
- **Alternatives considered.** A `| Option | Why not |` table. Only options that come from the PRs, the commits, the ticket, or the user. Never invent a rejected option to make the design look considered.
- **Assessment of impact.** One bullet per team or system, bold label then colon: `- **Airflow / DWH:** …`. This is the one place bold labels are the house style. Always include what is untested.
- **Plan / Steps.** A checklist. Each code step ends with its PR link: `- [ ] Push engine: SQL params and a connection per region. [#103 feat(push): accept SQL params and a connection id](https://github.com/acme/data-pipelines/pull/103)`. Non-code steps (Terraform apply, secrets, checkpoints) have no PR. There is no separate PR list.
- **Open questions.** Only questions that block a step or a decision.

## 3. Tables, code, diagrams

- RFCs often draw with ```` ```mermaid ```` flowcharts and paste screenshots. This skill replaces mermaid in Notion with rendered PNG diagrams in the house skin, placed with `<image source="file-upload://…" />`. Add a one-line caption under an image only if the heading above doesn't already say what it shows.
- Tables: a property/value table for what gets written, a comparison matrix with ✅/❌ when options differ on features, pipe tables for evidence counts.
- Code blocks: JSON payloads (current vs proposed), SQL snippets. Keep them short; link to the PR for the rest.
- Rejected options can stay visible struck through: `<s>Dedicated endpoint</s>`.

## 4. Voice

- English. "We" for decisions ("we decided", "we keep"), impersonal for analysis.
- Medium sentences, concrete nouns, exact names. Numbers stated plainly and sourced: "120,000 contacts (region id 1234567)". A worked back-of-envelope sum is welcome when it justifies a size ("3 metrics × 24 hours × 5,000 stations = 360,000 rows a day").
- Honest about gaps: "The CRM write itself is untested until the first production push." State what wasn't checked rather than smoothing it over.
- Plain writing: no em or en dashes, no "not X but Y" staging, no one-line closers, no triads for rhythm, sentence-case headings, no decorative bold. If the `humanizer` skill is available, apply its rules in embedded mode before publishing.
- Every fact must trace to a PR diff, a commit message, the ticket, the database, or the user. If a sentence needs a fact you don't have, ask or write a simpler sentence.

## 5. Notion markup to copy

- Heading: `# <span color="green">1. Problem / Motivations</span>`
- Callout: `<callout icon="💡" color="gray_bg">…</callout>`
- Placeholder hint (only in a template, never in a finished doc): `<i><span color="gray">…</span></i>`
- Toggle: `<toggle>Plan …</toggle>`; collapsible H2: `<toggle heading="h2">Title</toggle>`
- Columns: `<columns><column ratio="50">…</column><column ratio="50">…</column></columns>`
- Divider between H1 sections: `---`
- Date: `<date start="2026-01-15" />`
- Angle brackets inside code spans stay literal: `<code>push_crm_<region></code>`. Writing `&lt;region&gt;` there shows the entity text verbatim. In plain text, escape them as `\<region>` or `&lt;region&gt;`.

## 6. Worked example (fictional)

A partner, Northwind, wants usage properties from our product written onto its own CRM contacts, in two regional CRM accounts. Stack #101 → #104 in `acme/data-pipelines`:

- Callout: "Status: in review. The EU region is built and waiting on deploy steps; the US region is waiting on its token. Code: stack #101 → #104 (draft PRs), nothing deployed yet."
- 1: what the partner wants (properties as a table with "what is pushed"), why the existing CRM sync can't do it, "Constraints we found" (contact IDs unique per region only, no sandbox, 120,000 contacts, wrong-token risk), Out of scope.
- 3: Data model / Load / Matching / Push (with its guards as a numbered list) / Alternatives considered.
- 4: Airflow/DWH, the existing CRM sync (shared code, same defaults), the partner (what they must do), Testing limits.
- 5: checklist with PR links on the code steps, then open questions.
