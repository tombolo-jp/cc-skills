# Implement (F3)

## When to read this

Read this before writing the first markup or CSS derived from the design. In cc-task-skills terms
this is the implementation phase. It assumes F2 has produced values with their source nodes.

The rules here are about translation, not about style: each one is a place where a value that is
correct in the design produces a result that is wrong in a browser.

## Rules

1. **Give a background the extent the design gives it, not the extent of the section.** A band in the
   design is a node with its own size; elements that merely overlap it may be siblings outside it.
   Wrap exactly the nodes the band contains and apply the background to that wrapper. Why: a
   background stretched to the section lands under content the design keeps outside it.

   ```css
   /* the band, not the whole section */
   .hero-stage { background-image: url("…"); }
   ```

2. **Suspect doubled padding whenever a measured gap is about twice the design value.** Nested
   sections that each carry their own block padding add up. Zero the inner one in the nesting
   context rather than halving both. Why: the excess belongs to the nesting, so halving the
   component breaks it everywhere else it is used.
3. **Check what an existing selector will do to a new element before adding it.** Element selectors
   scoped to a container (`.list-item img`) reach every image you add later, including logos and
   icons. Narrow by class rather than winning a specificity fight. Why: a specificity fix holds
   until the next element is added, and the next fix has to be more specific still.

   ```css
   .list-item img { width: 100%; aspect-ratio: 4 / 3; }  /* reaches new images too */
   .list-photo   { width: 100%; aspect-ratio: 4 / 3; }  /* scoped to what it names */
   ```

4. **Turn fixed values into fluid ones where the design only fixes the endpoints.** A width or font
   size taken literally from two breakpoints will reflow badly between them — the classic symptom is
   a label that wraps to two lines only in the middle of the range. Use a range function and record
   the substitution in the deviations table. Why: the design states nothing about the widths between
   its two frames, which is exactly where the layout breaks.

   ```css
   .card-title { font-size: clamp(1rem, 0.85rem + 0.6vw, 1.25rem); }
   ```

5. **Centre what is meant to look centred, whatever the coordinates say.** When a design's
   coordinates place a glyph or icon off-centre — because it was nudged by hand — centre it and record the
   correction in the "corrected by measurement" table with both numbers. Why: reproducing the
   measurement faithfully reproduces the misalignment, and it is the misalignment, not the number,
   that the client sees.
6. **Reproduce a library's visual behaviour with its documented options first.** If matching the
   design needs a parameter outside the library's intended range — a fractional count where whole
   numbers are expected, for instance — treat that as a signal, not as a solution: such values can
   break the library's internal arithmetic. Choose the nearest supported configuration and record
   the difference. Why: such breakage appears only at some viewport widths, so it survives a review
   that looks at the two design widths.
7. **Set a library's motion-related options explicitly rather than relying on defaults.** Defaults
   commonly change behaviour based on the visitor's reduced-motion preference. Decide what the
   component should do in both states and write it down in code. Why: otherwise the component
   behaves differently on the reviewer's machine than on yours, with nothing in the code to explain
   the difference.
8. **Keep an element that must sit at the bottom of a flexible box aligned with `auto` margins, and
   express its spacing with padding.** Why: the automatic margin is the slack that absorbs differing
   content heights; replace it with a fixed value and the row of cards stops lining up at exactly
   the widths where one title wraps.
9. **Clip both axes when a shape can overflow in both.** `overflow-x: clip` leaves vertical
   overflow visible. Why: the horizontal scrollbar disappears, so the fix looks complete, while a
   decorative shape keeps spilling over the section below it.
10. **Leave a comment in the code at every intentional deviation** — one line, saying what the design
    value is and why it is not used. Why: the reasoning lives in the record document, but the person
    who would otherwise "fix" the value back is standing in the CSS.

## Don'ts

- **Don't stretch a background across the whole section with `inset: 0`.** Why: it lands under
  elements the design keeps outside the band, and text over a photograph becomes unreadable.
- **Don't fix a spacing discrepancy by halving a component's own padding.** Why: the component is
  then wrong everywhere else it is used; the excess belongs to the nesting, so fix it there.
- **Don't resolve an unintended style spill with `!important` or a deeper selector.** Why: it wins
  this round and loses the next; scoping by class is the only change that stops recurring.
- **Don't copy a fixed pixel value into CSS because the design shows it at two widths.** Why: the
  design says nothing about the widths between them, which is where the layout actually breaks.
- **Don't apply a minimum height expressed in line units to a box that contains images.** Why: the
  image height dominates and the constraint silently does nothing; put it on the text wrapper.
- **Don't reproduce a design mistake faithfully.** Why: faithfulness is not the goal — the reviewed
  outcome is. Implement the corrected version and record the correction.
- **Don't leave a deviation only in the record document.** Why: the person reading the CSS a month
  later will "fix" it back to the design value.

## Checklist

- [ ] Every background's extent matches the node it comes from, not the enclosing section.
- [ ] Every gap that measured about double the design value has been traced to its two sources.
- [ ] New elements were added without widening the reach of an existing selector.
- [ ] Values fixed only at breakpoint endpoints are fluid between them.
- [ ] Optical corrections are implemented and recorded with both numbers.
- [ ] Library components use documented option values; substitutions are recorded.
- [ ] Motion-related options are set explicitly, with the reduced-motion case decided.
- [ ] Bottom-aligned content still uses automatic margins; spacing is padding.
- [ ] Each intentional deviation has a one-line comment in the code and a row in the record.

## Exit criteria

Move to F4 when every section is implemented from recorded values, each deviation exists in both the
code comment and the deviations table, and no value was copied from the design without checking how
it behaves between the two widths the design specifies.
