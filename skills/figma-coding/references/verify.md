# Verify (F4)

## When to read this

Read this together with `<SKILL>/templates/comparison.md`, before taking the first screenshot. In
cc-task-skills terms this is the verification phase.

The procedure is written tool-agnostically: it names what must be true, not which driver produces it.
Any browser automation available in the session will do, headless included, and the manual steps can
be done in a real browser.

## Rules

### Before anything is photographed

1. **Prove the environment is healthy first.** Load the page and confirm that every stylesheet and
   script the page depends on returned a success status, and that **local assets return zero 404s**.
   Why this is rule 1: a page missing its shared CSS renders in a different colour scheme, at
   different offsets, and at a different total height. Every "difference" measured in that state is
   an artefact, and the real differences drown in them. This failure has consumed entire review
   rounds.
2. **Know which environment you are measuring.** A development server that injects CSS through
   scripts is right for dimensional measurement and screenshots; it is wrong for anything that
   depends on load order. Measure load-order-sensitive metrics against a production-like build, and
   build it immediately before measuring. Why: the injection produces a flash of unstyled content,
   which inflates layout-shift metrics into a failure that does not exist in production — and a
   stale build reports a result for code you no longer have.

### The screenshot procedure

3. **Follow all five steps below, in order, every time.** Why: each step removes one way a capture
   can look finished while showing something the visitor never sees.

   - **S1** Serve the page from the environment chosen above.
   - **S2** Set the viewport through the automation's viewport setting, at the width being verified.
   - **S3** **Replace every `loading="lazy"` with `eager` and reload.** Programmatic scrolling does
     not trigger lazy loading reliably, so images stay blank and implemented sections get reported
     as missing.
   - **S4** Wait for `document.fonts.ready` **and** for `decode()` on every image to settle.
   - **S5** Confirm that **no image has `naturalWidth === 0`**, then capture full page. The only
     images that may be left out of that count are the ones already written into the
     acceptable-noise list (rule 14) with their `src`; anything else at zero blocks the capture.

### Measuring

4. **Measure with the DOM, not with the eye.** Read geometry from the rendered boxes and compare the
   numbers with the design spec. Why: a screenshot cannot separate a fix from a rounding
   coincidence, so it belongs in the comparison document rather than in the verdict.
5. **Verify at the edges of every breakpoint, one pixel either side.** For each breakpoint used by
   the stylesheet *and* by any component library, check the value minus one, the value itself, and
   the value plus one. Stylesheets written mobile-first use lower bounds while many libraries use
   upper bounds. Include the narrowest width the project supports. Why: the two systems can both
   apply at exactly one width, and that single pixel is where the layout comes apart.
6. **Confirm horizontal overflow is zero at every width checked**, comparing the document's scroll
   width with its client width. Why: a full-page screenshot widens itself to fit the overflow, so
   the capture looks correct while the delivered page scrolls sideways.
7. **Check at least two rendering engines.** Why: line breaking differs between them, so a heading
   that fits on two lines in one engine takes three in another and changes the height of everything
   below it.
8. **Cross-check the automated browser against a real one.** Lazy loading, scroll behaviour, and
   sticky elements are the usual disagreements. Why: a defect that reproduces in only one of the two
   is a defect in the harness until proven otherwise, and fixing it in the page makes the page wrong.
9. **Set the viewport when creating the browser context, not by resizing the window.** Why: the override leaves the layout viewport and the window
   size inconsistent — the page appears shifted and cropped — and it survives page reloads, so every
   later measurement in that window is quietly wrong.
10. **Judge motion by sampling, not by a still.** Read a transform or a box dimension every few tens
    of milliseconds and confirm the values change monotonically. Why: a still frame cannot
    distinguish an animation from an instant jump.
11. **Use DOM-level restoration for regressions.** To confirm that a change caused an effect, restore
    the previous value in the live DOM and re-measure under identical conditions. Why: an older
    screenshot differs in build, fonts, and viewport as well as in the one value under test, so it
    cannot attribute the difference.

### Build-output checks

12. **Add a mechanical check for the "builds fine, ships wrong" class.** Template fragments that
    resolve to empty strings, output file names that lose their expected form, asset references that
    survive the build unresolved. Assert the presence of required strings and the absence of
    forbidden ones in the built output, and run it as part of the standard procedure. Why: all of
    these succeed at build time and are first noticed on the server you deployed to.

### The comparison document

13. **Produce three series per section: design, before, after.** Use one naming scheme for all of
    them — `<origin>-<viewport>-<section>` with `origin` one of `figma`, `before`, `after` — and put
    them in one table per section. Why: read side by side, the three series answer "did this change
    help?" without anyone having to remember what the page looked like. See
    `<SKILL>/templates/comparison.md`.
14. **List the known-acceptable noise before the first capture, and keep it in one place.**
    Third-party widgets that fail on a local host, aborted telemetry beacons, and the tracking
    pixels S5 may skip: each entry names the `src` or message and the reason. Then **every console
    error, and every zero-width image, that is not on the list must be fixed**. Why: written
    beforehand the list is a commitment; decided in the moment it becomes a way to dismiss the one
    broken image you were looking for.
15. **End the document with what remains**, each item pointing at its evidence node. Why: leftovers
    that are not written down are rediscovered from scratch in the next round.

## Don'ts

- **Don't screenshot before the health check passes.** Why: you will report artefacts, and the real
  differences will be inside the noise.
- **Don't skip the lazy-to-eager step.** Why: blank images get reported as unimplemented sections.
- **Don't resize with a device-metrics override.** Why: it corrupts the viewport for every later
  measurement in that window and does not reset on reload.
- **Don't verify only at the design's two widths.** Why: layouts break between breakpoints, and at
  the exact pixel where two rule systems overlap.
- **Don't accept a single engine or a single browser.** Why: line breaking and lazy loading are
  precisely where they disagree.
- **Don't evaluate performance on absolute scores** when the page inherits a shared bundle it does
  not control. Why: the score reflects the inherited bundle. Compare against a comparable existing
  page and use deltas.
- **Don't call a difference "fixed" from a screenshot alone.** Why: measure it; a picture cannot
  distinguish a fix from a coincidence of rounding.

## Checklist

- [ ] Shared and local assets all load; local 404s are zero; the check is recorded.
- [ ] The environment used matches what is being measured (dimensions vs. load order).
- [ ] All five screenshot steps were followed, including the zero-`naturalWidth` confirmation.
- [ ] Every image left out of that confirmation was already on the acceptable-noise list, by `src`.
- [ ] Measurements come from the DOM and are compared against the design spec values.
- [ ] Every breakpoint was checked at −1 / exact / +1, plus the narrowest supported width.
- [ ] Horizontal overflow is zero at every width checked.
- [ ] At least two engines, and both an automated and a real browser, were used.
- [ ] No window-resize API with device-metrics override was used at any point.
- [ ] Animations were confirmed by sampling values over time.
- [ ] The build-output check runs and passes.
- [ ] The comparison document has three series per section under one naming scheme.
- [ ] The acceptable-noise list exists, and no unlisted console error remains.
- [ ] Remaining items are listed with their evidence nodes.

## Exit criteria

Finish when the health check passes, every section has design / before / after in the comparison
document, measured values agree with the design spec or appear in the deviations table with a
reason, the breakpoint edges and both engines are clean, and the only console output is on the
acceptable-noise list.
