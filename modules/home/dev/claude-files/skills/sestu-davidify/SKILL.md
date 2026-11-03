---
name: sestu-davidify
description: Rewrite any text in the Slack writing style of David Sestu (BI / data at Sencrop) — "Hello" openers, one sentence per line without bullets, "pas de soucis", "du coup", franglais data jargon, missing accents, deadpan sarcasm. Use when the user says "davidify", "write like David", "à la David", or passes text to convert into David's style.
---

# Davidify

Rewrite the given text so it reads like a Slack message from David. Keep the meaning and every fact (names, numbers, dates). Change only the voice.

Output only the rewritten text, no commentary.

**Language:** French by default (80% of his messages). Use English only if the user asks for it or the text is clearly for an international channel — then apply section 7.

Style source: ~160 of his real Slack messages (Dec 2024 – Nov 2026).

## 1. Pick the register first

| Register | When | Length |
|---|---|---|
| **A. Explaining (pro)** | Sharing an analysis, explaining a limit, asking for something, pushing back | 2–8 lines |
| **B. Quick work reply** | Ack, taking a task, short answer | 1 line, 2–6 words |
| **C. Friends DM** | Lunch, after-work, gossip, venting | burst of 1–3 tiny messages, lowercase |

If the input is long and casual, split it into a burst of short messages (one per line, separated by a blank line, prefixed `—`).

## 2. Structure

**Openers**
- Register A: `Hello,` / `Hello <Prénom>,` / `Hello <Prénom> !` then content. **Never "Bonjour".** Mentions right after Hello: `Hello @François @Iryna si vous…`
- Sometimes `Hello` alone as a first message, the real content as a second message.
- Asking his manager for something: `Salut <Prénom>,`
- Replies start with an interjection: `Ah d'accord` · `Ah non` · `Arf` · `Bon` · `Oui` · `Non` · `Mais`
- Register C: `yo` or nothing.

**Body (register A)**
- **No bullets, ever.** One sentence per line, even for a list of facts.
- Reasoning order: context → limit/problem → what I did → conclusion or condition (`Si vous pressentez que…, il va falloir que…`).
- Blank line between two topics (`Pour le coté cohort, …`).

**Closers**
- Register A: `Bonne journée` (no punctuation) or an offer: `Si vous voulez <X>, dites le moi` · `si vous avez des remarques ou des commentaires` · `tell me if…`
- Register B/C: nothing, often no final period.
- Never ends his own request with "Merci". "Merci" only as a reply (`Merci pour les explications`).

## 3. Vocabulary

| Situation | Phrases |
|---|---|
| Accept | `Pas de soucis` · `Oui pas de soucis` · `Hello oui sans soucis` · `Ça marche !` · `Oui stp` |
| Take a task | `Je regarde ça` · `Je m'en charge` · `Je peux le faire` · `Oui bonne idée je vais faire ça` |
| Understood | `Ah d'accord` · `C'est ça :slightly_smiling_face:` |
| Send a file | `Voila` · `Voila si c'est plus clair` |
| Friends | `chaud` · `allez` · `vasi` · `mdr` · `x)` · `arf` · `en vrai` · `psk` · `auj` · `nan` |

**Connectors (register A):** `En revanche` · `Cependant` · `Par contre effectivement` · `Du coup` (very frequent, also at the end of questions: `Il faut utiliser quelle table du coup?`) · `A titre informatif` · `pour info` · `Malheureusement` · `en partant du principe que` · `Afin de` · `notamment` · `quitte à` · `Il s'agit de`

**Hedges:** `à mon avis` · `selon moi` · `je pense` · `Il me semblait` · `je ne sais pas trop` · `potentiellement` · `C'est peut être utile`

**Franglais (keep data/tech words in English):** `checké` · `je close l'incident` · `l'alarme a recover` · `patcher` · `faire sauter le point` · `cette data` · `un full load` · `le sizing` · `l'ownership` · `le template` · `des batchs` · `un bump` · `le thread` · `en remote` · `les trials` · `les farmers` · `CF.`

**Questions:** tag `non?` at the end (`doit avoir résolu le problème non?`) · either/or (`… ou alors nous en discutons en direct ?`)

## 4. Spelling & typography (his real mistakes)

- **Missing accents:** `Voila` · `recu` · `au cas ou` · `facon` · `acces` · `desactiver` · `coté` · `A titre informatif` · `la` for `là`. Mix `Ca` and `Ça`.
- **Missing hyphens:** `peut être` · `qu'entends tu` · `dites le moi` · `celle ci`
- **Typing slips:** `retiréés` · `préssentez` · `ameilloration` · `décrossant` · `merc`
- **Fast-typing grammar:** `il ne répondent` · `il ne sont présents` · `comment il comprends` · `on faisais` · `les a relancé` · `ils faut`
- **Dropped "ne":** `on a pas` · `j'arrive pas` · `j'ai pas testé ça encore`
- **Capitalized months** (`Mi-Novembre`, `fin Octobre`), **lowercase tools** (`databricks`, `chargebee`, `claude`, `google sheets`), `Hubspot`
- **Space before ? and ! is random:** `Ça marche !` / `C'est OK pour toi ?` / `aujourd'hui?` / `non?`
- **Anglicised spelling:** `connection` · `list` · `unlicenced`

Dosage:

| Register | Accents/hyphens | Typing slips | Dropped "ne" |
|---|---|---|---|
| A | 2–3 | 0–1 | rare |
| B | 1 | 0 | often |
| C | all dropped | 1 | always |

## 5. Tone

- **Calm, factual, deadpan.** Almost no enthusiasm, almost no emoji (`:slightly_smiling_face:` or `x)` at most once).
- **Pedagogical:** pre-empts misunderstanding, states method and limits (`A titre informatif, ces 5k zones ne correspondent pas directement à des farmers.`), says honestly when nothing comes out (`je ne vois pas grand chose ressortir`).
- **Pushback = factual list + one sharp closing line:** `François les a relancé 3 fois depuis hier, personne n'a répondu.` → `Il s'agit de faire une chose qu'Iryna ferait en 10 minutes maximum.`
- **Deadpan sarcasm** for annoying tools/processes, no smiley: `Ah non moi je trouve ça bien d'attendre 20 secondes sur un portail…` · `… doit avoir résolu le problème non?`
- **Venting (register C only):** `c'est une folie` · `C'est quoi ce bordel x)` · quote someone to show the absurdity (`Et t'as X qui vient dire "…"`).
- **Kind & practical:** offers to skip useless meetings, shares discoveries (`Je viens de découvrir que…`), admits own mistakes (`Je viens de comprendre que j'ai cassé…`), short apologies (`désolé pour la confusion`).

## 6. Real examples

```
Hello, je suis en train de travailler sur le template des documents de suivi de parc B2B.
J'ai une version 0, il va falloir itérer dessus, mais à mon avis vous pouvez déjà faire un retour.
Le template montre de la fausse donnée pour information.

Pour le coté cohort, j'ai fait quelques analyses, et mis à part quelques batchs très défaillants, je ne vois pas grand chose ressortir.

Si vous pouvez me faire un retour sur des points d'ameilloration sur la forme svp
Bonne journée
```

```
Malheureusement on a pas l'historique des addon. Je peux dire lesquels sont actifs, mais l'ajout d'un addon se passe par une modification de la subscription.
Le seul moyen de savoir ça est de passer par les "audit logs". Pour l'instant il ne sont présents que dans chargebee.
Si vous préssentez qu'il va y avoir des enjeux majeurs autour de ça, il va falloir que l'on ingère cela (je pense notamment à l'ARR).
```

```
Hello Martin !
Je ne sais pas si tu l'as remarqué, mais je viens de voir que ton pneu arrière droit est crevé.
Bonne journée
```

Register C burst:
```
— yo premier mai?
— chaud
```

## 7. English mode

Same structure (Hello, one sentence per line, no bullets, offer at the end). Simple French-built English: `several kind of` · `how it affect` · `an other` · `difficulties to open it` · lowercase `i` · space before `!`/`?` (`Yes !`, `export ?`). Short replies: `Here it is` · `Here is the data` · `Yes !`. Closer: `Have a good day.`

## Checklist before output

- [ ] Register chosen (A / B / C)
- [ ] Opener: `Hello` (never "Bonjour") or an interjection
- [ ] No bullets; one sentence per line
- [ ] At least one connector or tic (`du coup`, `pas de soucis`, `en revanche`…)
- [ ] Data/tech words kept in English
- [ ] Accent/hyphen drops per the dosage table
- [ ] No "Merci" closing on his own request
- [ ] All original facts preserved
