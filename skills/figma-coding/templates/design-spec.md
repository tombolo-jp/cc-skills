# Design spec — `<page or feature name>`

> Index of **measured** values. node-ids live in the node map. Every cell uses the format
>
> ```
> <value> — <source node-id | source: manual, from <who>, <date>> — <formula, or "measured directly">
> ```
>
> Example: `56px — 1234:5678 — 16 (font) × 1.5 (line height) + 16 + 16 (padding)`
> Manual mode: `56px — source: manual, from <who>, <YYYY-MM-DD> — measured directly`
>
> `TBD` means not yet measured; any `TBD` left here means this phase is unfinished.
> Mark a mobile value that is **not** a scaled version of its desktop counterpart with
> `not proportional to desktop`.

## Colour, type, shared decoration

| Item | Value | Source | Notes |
|---|---|---|---|
| `<role, e.g. accent>` | `<value>` | `1234:5678` | `<where it is used>` |
| `<heading scale step>` | `<size / line height / weight / tracking>` | `1234:5678` | `<desktop and mobile if they differ>` |
| `<corner radius>` | `<value>` | `1234:5678` | — |
| `<shadow>` | `<offset / blur / spread / colour>` | `1234:5678` | export bounds include the blur |

## Shared components

| Component | Dimension | Value — source — formula |
|---|---|---|
| `<button>` | height | `<value> — 1234:5678 — <formula>` |
| `<button>` | horizontal padding | `<value> — 1234:5678 — measured directly` |
| `<card>` | width | `<value> — 1234:5678 — <formula>` |

## Per-section measurements

### `<section name>`

| Item | Desktop | Mobile |
|---|---|---|
| section block padding | `<value> — 1234:5678 — <formula>` | `<value> — 1234:5678 — <formula>` |
| gap between items | `<value> — 1234:5678 — <child B start − child A end>` | `<value> — … — …` |
| `<element>` size | `<value> — 1234:5678 — measured directly` | `TBD` |

Repeat one block per section.

## Non-obvious shapes

| Shape | How it was established | Implementation approach |
|---|---|---|
| `<notch / curved band / cut corner>` | `<read from the SVG path of 1234:5678>` | `<CSS approach, or asset>` |

## Asset budgets

| Use | Limit | Basis |
|---|---|---|
| `<hero image>` | `<n KB>` | `<project convention>` |
| `<in-section illustration>` | `<n KB>` | `<project convention>` |
| pixel dimensions | at most twice the display size | never export at 3x |

## Changed on purpose

Deviations from the design that are intentional. Without a row here, the deviation is re-reported as
a defect in every later review.

| # | Item | Design says | Implemented as | Why |
|---|---|---|---|---|
| 1 | `<item>` | `<value — 1234:5678>` | `<value>` | `<reason>` |

## Corrected by measurement

Values where the design data was read one way and the rendered result proved otherwise.

| # | Item | First reading | Measured | What the discrepancy was |
|---|---|---|---|---|
| 1 | `<item>` | `<value — 1234:5678>` | `<value>` | `<e.g. composited translucent fill; export bounds included shadow>` |

## Unresolved

| # | Item | Blocking what | Owner |
|---|---|---|---|
| 1 | `<TBD value or designer question>` | `<which section cannot be finished>` | `<designer / client / us>` |
