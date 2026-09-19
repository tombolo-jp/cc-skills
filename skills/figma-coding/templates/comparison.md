# Design vs. implementation — `<page or feature name>` (`<date>`)

- **Design**: file key `<fileKey>`, desktop frame `1234:5678`, mobile frame `1234:5678`
- **Implementation**: `<environment used>`, captured at `<desktop width>` and `<mobile width>`
- **Health check**: shared assets all loaded, local 404s `<n>` (must be 0), images with
  `naturalWidth === 0` `<n>` (must be 0, tracking pixels excluded and listed below)
- **Image naming**: `<origin>-<viewport>-<section>.png`, where `origin` is `figma`, `before`, or
  `after`, and `viewport` is `pc` / `sp` or the width in pixels. All images are in `./attachments/`.

---

## 1. `<section name>`

| | Image |
|---|---|
| Design `1234:5678` | ![](./attachments/figma-pc-<section>.png) |
| Before | ![](./attachments/before-pc-<section>.png) |
| After | ![](./attachments/after-pc-<section>.png) |
| Design (mobile) `1234:5678` | ![](./attachments/figma-sp-<section>.png) |
| After (mobile) | ![](./attachments/after-sp-<section>.png) |

**Result**

- `<what changed, stated as a measured value rather than an impression>`
- `<deviation from the design, with the row number it has in the "changed on purpose" table>`

Repeat one block per section.

---

## Widths checked

| Width | Horizontal overflow | Notes |
|---|---|---|
| `<narrowest supported>` | `<0>` | — |
| `<breakpoint − 1>` / `<breakpoint>` / `<breakpoint + 1>` | `<0 / 0 / 0>` | both rule systems apply at the exact value |
| `<library breakpoint ± 1>` | `<0>` | — |

Engines checked: `<engine A>`, `<engine B>`. Real browser cross-check: `<done / not done>`.

## Accepted console noise

| Message | Why it is acceptable |
|---|---|
| `<third-party widget failing on a local host>` | `<not part of this work; reproduces on an existing page>` |

Anything not listed here was fixed.

## Remaining

| # | Item | Evidence node | Why it is still open |
|---|---|---|---|
| 1 | `<item>` | `1234:5678` | `<out of scope / awaiting a designer answer / deferred with agreement>` |
