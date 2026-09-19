# Fetch (F1)

## When to read this

Read this before the first `get_figma_data` call, and keep it open for the whole fetching pass. In
cc-task-skills terms this spans the design and implementation phases. Asset exports are covered
separately in `assets.md`.

## Rules

### Tool contract

| Tool | Required | Optional | Convention |
|---|---|---|---|
| `get_figma_data` | `fileKey` | `nodeId` (`1234:5678`; a nested instance uses the `I…;…` form), `depth` | **Do not pass `depth`.** The tool's own description says not to unless explicitly requested |
| `download_figma_images` | `fileKey`, `nodes[]` (each with `nodeId` and `fileName`; an image fill also needs its `imageRef`), `localPath` | `pngScale` (defaults to 2) | `localPath` is relative to the MCP server's image directory, normally the project root |

`1234:5678` above is a format example, not a real node.

### Fetch order and scope

1. **Fetch in this order: whole file once, then section by section, then the mobile frames, then
   assets.** The first call is for structure only — which top-level frames exist and what they
   contain. Why: every later call is then aimed at a node you have already seen, which is what keeps
   the call count inside the budget.
2. **Read every node at full depth, with `depth` left unset.** Why: a shallow read returns parents
   without the children that hold the actual colours, text, and coordinates, and it returns them
   *successfully*, so the gap is invisible. Every shallow read is re-read later at full depth.
3. **Ask for one section per call.** Why: a whole-page request is
   both the most expensive call against the rate limit and the one most likely to be truncated by
   context limits — and a truncated response looks exactly like a complete one.
4. **Fetch both the desktop and the mobile frames for every section.** Then produce two inventories:
   elements that exist only in the mobile design, and **elements that exist on desktop and are
   deliberately absent on mobile**. Why: the second list is the one that gets lost, and without it
   "the image is missing on mobile" is reported as a bug for the rest of the project.
5. **Settle the count of repeated elements by a deep traversal, not by looking at the canvas.** A
   component set with variants multiplies the apparent count: what looks like eighteen cards can be
   six unique cards in three states. Count the unique children, and write the number and its
   evidence node into the node map. Why: the inflated number propagates into data files and CSS,
   where it is much more expensive to correct than here.
6. **Derive spacing from coordinates when the file has no Auto Layout.** The gap is the difference
   between a sibling's start coordinate and the previous sibling's end coordinate, both relative to
   the same parent. Record the subtraction, not just the result. Why: only the subtraction shows
   which two nodes a gap belongs to, so only it can be re-checked after the design moves.
7. **Record each node-id as you use it.** The node map is written during fetching, not after it.
   Why: re-finding an id costs another call against a budget you cannot refill.

### Reading traps

These are properties of the returned data, not of the design.

8. **`fills: []` on an instance means "no override", not "no colour".** The colour lives on a node
   inside the component. Descend into the component, and confirm against an exported image's actual
   pixels before writing a colour into the spec. Why: an empty array reads as "unstyled", which leads
   straight to a guessed default.
9. **What reads as text may be an image.** Headings are often outlined, and a node whose fill type is
   an image is a picture of text: it cannot be restyled, its font will not be in the type scale, and
   exporting it as SVG produces a wrapper around a bitmap (see `assets.md`). Why: it is transcribed
   as text, and the difference only appears when the type scale changes.
10. **Establish white and near-white shapes from the SVG `path` data.** A white shape on a white
   background is invisible in a PNG, so notches, cut corners, and inner shapes disappear from a
   raster export. Why: the missing shape is
   then implemented as a plain rectangle, and the omission is invisible in a screenshot too.
11. **Take colours from the node's fill and opacity, or from a sampled pixel.** Overlaid translucent fills produce
   composited pixels that read as a different colour entirely; a dark shape at partial opacity on
   white reads as mid-grey. Sample the actual pixel value, or read the fill and opacity from the
   node. Why: the sampled colour is right for one background and wrong everywhere else.
12. **Check the mock for internal contradictions before treating it as a specification.** A carousel
   captured mid-drag, a card grid whose card width times count plus gaps exceeds the frame width, a
   pagination indicator that disagrees with the visible slide — each means the frame is a snapshot of
   an interaction, not a statement of intent. Do the arithmetic; when it fails, raise it as a
   question for the designer. Why: a faithfully implemented contradiction is reported back to you
   as an implementation bug.
13. **A node that is visually inside a band may be outside it in the tree.** Check the parent before
   assuming an element belongs to the section it overlaps. Why: this decides how far a background
   extends, and getting it wrong puts text on top of a photograph (see `implement.md`).

## Don'ts

- **Don't pass `depth`.** Why: shallow data is indistinguishable from complete data in the response,
  so the error surfaces only as a wrong implementation.
- **Don't request an entire page in one call.** Why: it is the most expensive call you can make and
  the most likely to be silently truncated.
- **Don't skip the mobile frames "because the layout is obviously the same".** Why: the differences
  that matter are usually removals, and a removal is invisible unless you look at both.
- **Don't infer a repeated element's count from the rendered canvas.** Why: variants and loop copies
  inflate it, and the inflated number then propagates into data files and CSS.
- **Don't accept a colour, a corner radius, or a shadow read off an instance with empty fills.**
  Why: those values are on the component's internals; empty means unchanged, not undefined.
- **Don't implement a value taken from a frame that fails its own arithmetic.** Why: you would be
  encoding a design mistake, and it will be reported as an implementation bug.
- **Don't refetch a node you already have to "double-check" a number.** Why: the budget is small;
  re-read your own record instead, which is why the record has to carry the source node.

## Checklist

- [ ] The structural call was made once, and every later call names a specific node.
- [ ] No call passed `depth`.
- [ ] Every section has been fetched at both desktop and mobile widths.
- [ ] The "mobile-only elements" and "deliberately absent on mobile" lists both exist.
- [ ] Repeated elements have a unique count with the traversal that established it recorded.
- [ ] Spacing values state whether they came from layout properties or from coordinate subtraction.
- [ ] Every fetched node-id is in the node map with what it contains.
- [ ] Contradictions found in the mock are listed as questions, not implemented.
- [ ] The number of calls made is recorded against the budget agreed in F0.

## Exit criteria

Move on when every in-scope section has been fetched at both widths without `depth`, the node map
lists each id used, repeated-element counts are settled by traversal, the mobile absence inventory
exists, and any contradiction in the design has been raised rather than resolved by assumption.
