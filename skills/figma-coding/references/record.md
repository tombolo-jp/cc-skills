# Record (F2)

## When to read this

Read this together with `<SKILL>/templates/node-map.md` and `<SKILL>/templates/design-spec.md`, just
before writing the first record document. In cc-task-skills terms this spans the design and
implementation phases. Records are written *while* fetching and implementing, not reconstructed
afterwards.

Two documents come out of this phase: the **node map** (which node-id holds what) and the **design
spec** (what was measured, and how). A third, the comparison document, belongs to F4.

## Rules

1. **Write every measured value in three parts: the value, the source node, and how it was obtained.**

   ```
   <value> — <source node-id | source: manual, from <who>, <date>> — <formula, or "measured directly">
   ```

   Why three parts: a bare number cannot be re-checked without spending another API call, and after
   a design update you cannot tell which numbers are still valid. In manual mode there is no node-id,
   so the second part says where the number came from instead — never leave it empty.
2. **State the derivation when a value is computed.** A spacing derived from coordinates records the
   subtraction; a height derived from type records the font size, line height, and padding that make
   it up. Why: the formula is what lets a reviewer disagree with the number; without it the only
   available response is to measure everything again.
3. **Say when desktop and mobile are not proportional.** If a value is not a scaled version of its
   desktop counterpart, mark it explicitly. Why: the default assumption is proportionality, and an
   unmarked value will be "corrected" by the next person into a scaled one.
4. **Keep a table of deliberate deviations from the design.** One row per deviation: what the design
   says, what was implemented, and the reason. Why: without it, every later review re-reports the
   same deviation as a defect, and the reason has to be reconstructed from memory.
5. **Keep a separate table of readings corrected by measurement.** When the implemented value came
   from measuring the rendered result rather than from the design data, record both numbers and what
   the discrepancy turned out to be. Why: this table is how the design data's reliability is judged,
   and a single entry changes how much of the rest you check twice.
6. **Route design-side gaps to a designer-questions list.** Contradictory mocks, missing states,
   values that only exist on one breakpoint: record them as open questions with the evidence node.
   Do not close a gap by choosing a value yourself and writing it in as measured. Why: once written
   in the measured column, a chosen value is defended in review as if it had been measured.
7. **Mark unmeasured cells `TBD`.** A `TBD` remaining in the design spec means F2 is not finished.
   Why: an empty cell is indistinguishable from a measured zero.
8. **Update the record in the same change as the thing it describes.** When an asset is replaced or a
   data set is re-fetched, update its scope, count, and provenance rows at the same time. Why: a
   record that lags by one change is still read as current.
9. **Place documents by the resolution order in `<SKILL>/SKILL.md`**, and name the measured-values file
   `design-spec.md`. Do not use `token` or `key` in any file name you create. Why: permission rules
   commonly deny those paths, which makes the document unreadable to the tools that need it.
10. **Mark every value supplied by a human as `source: manual`, with who supplied it and when.** This
    is the whole of F2's job in manual mode: F1 is skipped, so the record is the only place the
    provenance exists. Why: a manual value and a measured one are indistinguishable once written
    down, and the manual one has no node to go back to when the design changes.
11. **Record the source file's identity at the top of the node map.** File key, your access level,
    last-modified timestamp, and — when more than one file exists — which sections each one governs.
    Why: values from a duplicate file look exactly like values from the authoritative one.

## Don'ts

- **Don't write a value without its source node.** Why: it cannot be verified or refreshed, so the
  next design change forces a full re-measurement.
- **Don't record a rounded value as if it were the measurement.** Why: rounding twice (once in the
  record, once in the CSS) produces drift that shows up as a one-pixel misalignment nobody can trace.
- **Don't let the design spec hold conclusions about the implementation** ("this is fine at all
  widths"). Why: it is an index of measured values; verification results belong in the comparison
  document, and mixing them makes stale claims look measured.
- **Don't copy a value from one breakpoint to the other.** Why: proportionality is an assumption, and
  rule 3 exists because it is frequently false.
- **Don't resolve a designer question by choosing a plausible value.** Why: the choice becomes
  indistinguishable from a measurement, and it will be defended as one in review.
- **Don't leave a deviation undocumented because it is small.** Why: small unexplained deviations are
  exactly what a pixel comparison surfaces, and each one costs a review round.

## Checklist

- [ ] The node map names the source file, the access level, and the last-modified timestamp.
- [ ] Every section in scope has a node-id row, including mobile frames and recorded absences.
- [ ] Every value in the design spec has value, source, and formula-or-"measured directly".
- [ ] Every value that came from a person rather than from the file carries `source: manual` with
      the supplier and the date.
- [ ] Non-proportional desktop/mobile pairs are marked as such.
- [ ] The "changed on purpose" table exists and has a reason in every row.
- [ ] The "corrected by measurement" table exists with both the original reading and the measurement.
- [ ] Designer questions are listed with evidence nodes and none is silently resolved.
- [ ] No `TBD` remains, or each remaining one is listed as blocking in the exit report.
- [ ] Asset rows match the files actually present, including provenance and deletion reasons.
- [ ] No created file name contains `token` or `key`.

## Exit criteria

Move to F3 when both documents exist at their resolved locations, every value carries its source and
derivation, the two mandatory tables are present, designer questions are recorded rather than
resolved, and no `TBD` remains in a value the implementation needs.
