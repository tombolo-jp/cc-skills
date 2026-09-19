# Assets (F1, export)

## When to read this

Read this before the first `download_figma_images` call. In cc-task-skills terms this belongs to the
design and implementation phases, alongside `fetch.md`.

## Rules

1. **Decide whether the node can be exported at all, before calling.** Why: these three shapes fail
   without an error, so the retry that follows spends quota on an outcome that cannot change.

   | Shape | What happens | Do instead |
   |---|---|---|
   | No wrapping parent — the pieces are siblings directly under the page frame | there is no single node to export | export the siblings separately and compose them in CSS, or ask for a grouping frame |
   | A bare rectangle with no children | the export is blank or a flat fill | take the parent one level up, or reproduce it in CSS |
   | An individual instance with no parent frame (common on mobile variants) | export succeeds but contains only part of what you see | export the component or the section frame instead |

2. **Expect the exported dimensions to differ from the layout values.** Shadow blur and spread are
   included in the exported bounds, so an export can be tens of pixels larger in each axis than the
   node's layout box. Size CSS from the layout value; use the export only for the picture. Why: a box
   sized from the export is larger than the design by the blur radius, and everything below it moves.
3. **Decide `preserveAspectRatio` per SVG, at export time.** The default preserves the ratio and
   letterboxes the artwork inside a box of a different shape — which reads as a CSS bug when a card
   changes proportion between breakpoints. If the artwork is meant to stretch with its container,
   set it to `none`; otherwise keep the default deliberately. Why: the symptom appears in CSS while
   the cause is in the file, so it is debugged in the wrong place.
4. **Check whether an "SVG" is really a bitmap.** A node whose fill is an image — an outlined
   heading, a flattened illustration — exports as an SVG wrapper around an embedded raster. It is
   larger than the equivalent PNG and does not scale. Export those as PNG at 2x instead. Why: the
   file extension says vector, so nobody checks it again.
5. **Build a size inventory immediately after exporting.** One row per file: pixel dimensions, byte
   size, where it is used, and its intended display size. Compare each row against the project's
   per-use budgets and against the "no more than twice the display size" rule. Why: after the
   context is gone, an oversized file can only be found by re-deriving every display size.
6. **Size a set of images with differing aspect ratios on one axis only.** Constrain
   one axis as a proportion of the container and let the other be automatic. Why: a shared height
   stretches the odd one out, and a stretched logo is noticed by the client before anything else.
7. **Record provenance for every asset.** Where it came from (exported from the design, supplied by
   the client, produced by re-encoding), what it replaced, and — for anything deleted — why. Why: an
   asset with no provenance cannot be regenerated after a design update.
8. **Re-encode supplied assets that exceed the budget, and record the before and after.** Note the
   method used. Why: without it the same file is re-optimised by guesswork, with a different result
   each time.

## Don'ts

- **Don't size a CSS box from an exported image's dimensions.** Why: shadows are baked into those
  dimensions, so the box comes out larger than the design and everything below it shifts.
- **Don't export at 3x "to be safe".** Why: it multiplies transfer weight for a difference no display
  shows at these sizes; 2x is the ceiling.
- **Don't accept an SVG export of an outlined heading.** Why: it embeds a bitmap, so you get the file
  size of a raster with the compatibility profile of a vector, and it will not scale.
- **Don't retry a blank export with different parameters.** Why: blankness is structural (rule 1);
  retries consume the rate-limit budget without changing the outcome.
- **Don't delete an unused exported asset silently.** Why: the next session re-exports it, spending
  quota to rediscover the same decision. Record the deletion and the reason.
- **Don't put `token` or `key` in an asset's file name.** Why: permission rules commonly deny those
  paths, and the asset becomes unreadable to the tooling that needs it.

## Checklist

- [ ] Every export target was checked against the three unexportable shapes first.
- [ ] `localPath` points inside the project, at the directory the project uses for such assets.
- [ ] CSS dimensions come from layout values, not from the exported file's dimensions.
- [ ] Each SVG has a deliberate decision recorded for aspect-ratio behaviour.
- [ ] No exported SVG contains an embedded bitmap.
- [ ] A size inventory exists with dimensions, bytes, use, and display size for every file.
- [ ] No image set shares a fixed height across differing aspect ratios.
- [ ] Every asset has provenance, and every deletion has a reason, in the node map.
- [ ] Every node that could not be exported is in the node map with its failure type and the
      alternative taken, so it is not attempted again.

## Exit criteria

Move on when every needed asset exists in the project's asset directory, the size inventory is
complete and within budget, no export is a bitmap-in-SVG or a blank, and provenance is recorded for
each file.
