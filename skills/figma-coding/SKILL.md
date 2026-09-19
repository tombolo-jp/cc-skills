---
name: figma-coding
description: Rules and checklists for turning a Figma design into code with the Figma MCP server (figma-developer-mcp), so that the first implementation matches the design and manual rework rounds are avoided. Use for any design to code work: working from a Figma file or a design handoff, reading a design with get_figma_data or download_figma_images, implementing a pixel-perfect or design-faithful layout, recording node-id or design spec values, or running visual regression against a design.
---

# Figma-based coding

A conventions-and-checklists skill for the whole path from a Figma file to shipped markup and CSS.
It runs nothing by itself and takes no arguments: it supplies the rules, the traps to avoid, and the
exit criteria for each phase, plus templates for the records you leave behind.

The rules exist because design-to-code rework is almost never caused by careless CSS. It is caused by
**fetching too little, misreading what was fetched, exporting assets that do not mean what they look
like, translating Figma values into CSS that behaves differently, and verifying in an environment that
manufactures differences of its own.** Each phase below closes one of those.

## Phases

| Phase | What it covers | Reference |
|---|---|---|
| **F0** Prerequisites | MCP connectivity and PAT hygiene, rate-limit budget, an Auto Layout spike, deciding what you will *not* fetch, pinning the source file | `<SKILL>/references/prerequisites.md` |
| **F1** Fetch | Fetch order (whole → section → PC *and* mobile), never narrowing `depth`, settling repeated-element counts, reading traps in the returned data | `<SKILL>/references/fetch.md` |
| **F1** Assets | Which nodes cannot be exported and what to do instead, why export sizes differ from layout values, SVG aspect handling, size budgets, provenance | `<SKILL>/references/assets.md` |
| **F2** Record | The measurement format (value + source node + formula), the two mandatory "changed on purpose" / "corrected by measurement" tables, unresolved questions | `<SKILL>/references/record.md` |
| **F3** Implement | Figma→CSS translation traps: background extent, doubled padding, selector spill, fixed values that reflow at in-between widths, optical centring | `<SKILL>/references/implement.md` |
| **F4** Verify | Environment health first, the five-step screenshot procedure, mechanical measurement, breakpoint edges and engine differences, the comparison document | `<SKILL>/references/verify.md` |

**Do not preload all references.** Read each one when you reach its phase, and read
`<SKILL>/templates/*` only just before you write the file it is a template for. Loading everything up front
costs context you will need for the design data itself.

| When | Read |
|---|---|
| Skill start (always, and only this one) | `<SKILL>/references/prerequisites.md` |
| Before the first `get_figma_data` call | `<SKILL>/references/fetch.md` |
| Before the first `download_figma_images` call | `<SKILL>/references/assets.md` |
| Before writing the first record document | `<SKILL>/references/record.md` + `<SKILL>/templates/node-map.md` + `<SKILL>/templates/design-spec.md` |
| Before writing the first CSS or markup | `<SKILL>/references/implement.md` |
| Before taking the first screenshot | `<SKILL>/references/verify.md` + `<SKILL>/templates/comparison.md` |

**On start, print at most five lines**: the phase table above in short form, which phase you are in,
and that `prerequisites.md` has been read. Do not restate the rules back to the user.

## Which MCP server

This skill assumes **Figma-Context-MCP** (`figma-developer-mcp`, personal access token), exposing
`get_figma_data` and `download_figma_images`. The OAuth-based official Figma MCP server is out of
scope: its tool names and parameters differ, and the rules below refer to the PAT flow by name.

```
Are the figma MCP tools present?
├─ yes → proceed to F0; if a call fails, triage with curl (401 / 404 / 403) per prerequisites.md
└─ no  → STOP and ask which of the two applies:
         (a) configure the server — copy <SKILL>/templates/mcp.json.example to .mcp.json,
             add .mcp.json to .gitignore (prerequisites.md rule 2), supply the token
             through an environment variable, then restart the session
         (b) MANUAL mode — a human supplies measurements and exported assets.
             F1 is skipped, F2 records every value with `source: manual`.
```

**Never infer design values because the MCP server is unavailable.** A guessed value is
indistinguishable from a measured one once it is written down, and it will be defended in review as
if it were measured. Manual mode exists so that the record keeps saying where each number came from.

## Where the records go

Three documents come out of this skill: a **node map** (an index of node-ids), a **design spec** (an
index of measured values), and a **comparison** document (design vs. before vs. after). Resolve their
location in this order and ask only if both of the first two fail.

| Order | Condition | Node map / design spec | Comparison |
|---|---|---|---|
| 1 | `.claude/docs/` exists | `.claude/docs/figma-node-map.md`, `.claude/docs/design-spec.md` | the task's own record directory if the project has one, else `.claude/docs/figma-comparison/<date>.md` |
| 2 | `docs/` exists | `docs/figma/node-map.md`, `docs/figma/design-spec.md` | `docs/figma/comparison/<date>.md` |
| 3 | neither exists | ask once, then default to `.claude/docs/` | same |

Comparison images live in `attachments/` or `images/` next to the comparison document.

**Do not put `token` or `key` in any file name you create.** Tool permission rules commonly deny
paths matching those words, and a record document that cannot be read back is worse than no record.
Name the measured-values file `design-spec.md`, not `design-tokens.md`.

## Questions you may ask

At most three, and only these:

1. Where records go — only when neither `.claude/docs/` nor `docs/` exists.
2. Whether to proceed in manual mode — only when the MCP tools are absent.
3. Which file is authoritative — only when more than one Figma file could be the source.

Everything else is decided by the rules in the references, or recorded as an open question for the
designer rather than resolved by guessing.

## Stop conditions

Stop and report rather than continue degraded:

| Condition | Why stopping is right |
|---|---|
| MCP absent and manual mode declined | The only remaining path is guessing values |
| API rate limit reached | List fetched and unfetched nodes with a priority order so the next session resumes instead of refetching, and offer manual mode as the alternative to waiting |
| Verification environment unhealthy (shared CSS/JS not loading, local assets 404) | Every "difference" measured in that state is an artefact; reporting them buries the real ones |
| A single source file cannot be pinned | Two files disagreeing silently is the most expensive failure in this workflow |

## Cloud sessions

- **The container is discarded.** Record documents and exported assets only survive if they are
  committed. Say so at the end of the run.
- **The token must be supplied by the environment**, through the environment-variable setting of the
  cloud environment or a setup script. There is no local `.env` to read.
- **Exported images count as repository content.** Check the project's asset conventions before
  committing binaries, and record provenance either way.
- **Browser automation is tool-agnostic here.** F4 is written as a procedure, not as commands for a
  particular driver; use whatever the session has, headless included.

## If you use cc-task-skills

The phases map onto that workflow as follows. This is a convenience mapping only — nothing in this
skill depends on those skills being installed, and nothing here writes to their files.

| Phase | Roughly corresponds to |
|---|---|
| F0, F1, F2 | design phase (`task-design`) |
| F1, F2, F3 | implementation phase (`task-dev`) |
| F4 | verification phase (`task-verify`) |

## Enabling this skill

`<SKILL>` below means this skill's own directory. Installed as a plugin it is
`${CLAUDE_PLUGIN_ROOT}/skills/figma-coding/`; copied by hand it is `~/.claude/skills/figma-coding/`
or `<project>/.claude/skills/figma-coding/`. Do not hard-code either form — references and templates
are addressed as `<SKILL>/references/*.md` and `<SKILL>/templates/*`.

As a plugin the skill is available in cloud sessions as well; a hand-copied personal skill is not.
