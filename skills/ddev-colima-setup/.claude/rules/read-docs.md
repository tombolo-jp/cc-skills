---
globs: ["SKILL.md", "scripts/**", "templates/**"]
---
Before starting work, read `.claude/docs/architecture.md` to identify which additional
docs are relevant, then read those docs.

| Task | Read |
|---|---|
| Change how files are generated / add a CLI flag / add a placeholder | `.claude/docs/generator.md` |
| Edit any file under `templates/` | `.claude/docs/templates.md` (+ `generator.md` for the placeholder contract) |
| Change Colima VM settings, DDEV config, MariaDB/PHP tuning | `.claude/docs/runtime-contracts.md` |
| Change the generated setup doc (`templates/setup.md`) | `.claude/docs/runtime-contracts.md` |
| Change the skill's invocation surface (args, steps, description) | `SKILL.md` + `.claude/docs/generator.md` |

`runtime-contracts.md` records ordering rules and irreversible operations that were each
learned from a real failure. Read it before changing any tuning value or default.
