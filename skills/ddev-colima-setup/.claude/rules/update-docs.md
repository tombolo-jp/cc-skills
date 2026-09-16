---
globs: ["SKILL.md", "scripts/**", "templates/**"]
---
After completing work, if your changes affect any pattern documented in `.claude/docs/`,
update the relevant doc(s). Keep updates minimal and factual.

| Change | Update |
|---|---|
| Added/removed/renamed a `__PLACEHOLDER__` | `architecture.md` placeholder index, `generator.md` |
| Added/removed a template or changed a destination path | `architecture.md` file index, `generator.md` template→destination map |
| Added/removed/renamed a CLI flag or changed a default | `generator.md`, `SKILL.md` input tables, and `generate.sh`'s own header comment block (lines 2–30, which `usage()` prints) |
| Changed validation or a warning threshold | `generator.md` |
| Changed a cross-file reference (profile name, container name, path) | `templates.md` cross-file coupling table |
| Changed a tuning value, a default, or an ordering requirement | `runtime-contracts.md` |
| Discovered a new failure mode or upstream bug workaround | `runtime-contracts.md` known-issues table, and `templates/setup.md` troubleshooting table |

Any behavioral change to a template must also be reflected in `templates/setup.md` —
it is the runbook the end user follows, and stale instructions are a real failure.
