# Figma node map — `<page or feature name>`

> Index of node-ids. Measured values live in `design-spec.md`; connection and token handling live in
> the F0 notes. Replace every `<…>` placeholder. `1234:5678` is a format example, not a real node.

## Source file

| Item | Value |
|---|---|
| File key | `<fileKey>` (`<file name>`) |
| Access level | `<owner / editor / viewer>` — viewer means read-only operations only |
| Last modified | `<YYYY-MM-DD>` |
| Authoritative for | `<all sections / the sections listed below>` |
| Second file (if any) | `<fileKey>` — authoritative for `<sections>`; the other file is stale for those |
| Spacing derivation | `<Auto Layout / derived from sibling coordinates>` (from the F0 spike) |

## Top-level frames

| Frame | node-id | Size |
|---|---|---|
| `<desktop frame>` | `1234:5678` | `<W>×<H>` |
| `<mobile frame>` | `1234:5678` | `<W>×<H>` |
| `<parts / library frame>` | `1234:5678` | `<W>×<H>` |

## Sections (desktop)

| # | Section | Parent node-id | Key child nodes |
|---|---|---|---|
| 1 | `<section>` | `1234:5678` | `1234:5678` (`<what it is>`), `1234:5678` (`<what it is>`) |
| 2 | `<section>` | `1234:5678` | `<…>` |

## Sections (mobile)

| # | Section | node-id | Notes |
|---|---|---|---|
| 1 | `<section>` | `1234:5678` | `<mobile-only element, or a difference from desktop>` |

### Deliberately absent on mobile

Elements that exist on desktop and are **intentionally not rendered** on mobile. Absence recorded
here is a specification; absence not recorded here will be reported as a defect.

| Element | Desktop node-id | Evidence that it is absent |
|---|---|---|
| `<element>` | `1234:5678` | `<mobile frame node-id, and what is in its place>` |

## Repeated elements

| Element | Apparent count | Unique count | How the unique count was established |
|---|---|---|---|
| `<card / slide / tab>` | `<n>` | `<n>` | `<traversal of node 1234:5678; variants × states>` |

## Exported images

| File | Source node-id | Format / scale | Origin | Notes |
|---|---|---|---|---|
| `<name.png>` | `1234:5678` | `<png 2x / svg>` | `<exported / supplied / re-encoded>` | `<replaces …, or aspect-ratio handling>` |

### Nodes that could not be exported

Without this table the next session spends quota rediscovering the same failure.

| Node-id | Failure | What was done instead |
|---|---|---|
| `1234:5678` | `<no wrapping parent / childless rectangle / parentless instance>` | `<exported siblings separately / took the parent one level up / asked for a manual export>` |

### Removed assets

| File | Why it was removed |
|---|---|
| `<name>` | `<not used after …, superseded by …>` |

## Known constraints of this file

- `<e.g. most frames are absolutely positioned, so spacing comes from coordinate subtraction>`
- `<e.g. one section exists only as a flattened image>`
- `<e.g. a section is out of scope and was never fetched>`

## Reading traps found in this file

Record each trap once, with the node that demonstrates it, so the next session does not rediscover it.

| Trap | Where it appeared | What is actually true |
|---|---|---|
| Empty `fills` on an instance | `1234:5678` | the colour is on `<node>` inside the component |
| Text that is an image | `1234:5678` | outlined heading; cannot be restyled, export as raster |
| Shape invisible in a raster export | `1234:5678` | read the SVG `path` to get the outline |
| Mock contradicts itself | `1234:5678` | `<what the arithmetic shows>`; raised as a designer question |

## Open questions for the designer

| # | Question | Evidence node | Status |
|---|---|---|---|
| 1 | `<question>` | `1234:5678` | `<open / answered on YYYY-MM-DD: …>` |
