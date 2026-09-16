---
name: setup-project-docs
description: Analyze the project codebase and set up .claude/docs/ reference documents, .claude/rules/ rule files, and update CLAUDE.md. Use when starting a new project or reorganizing existing documentation.
disable-model-invocation: true
---

# Project Documentation Setup

You are setting up Claude Code reference documentation and rules for this project.
Follow these phases in order. Ask the user for clarification when needed.

---

## Phase 1: Project Analysis (Agent Teams)

1. Check if `CLAUDE.md` exists in the project root. If not, propose creating one.
2. Check if `.claude/docs/` and `.claude/rules/` already exist. If they contain files, ask the user whether to overwrite or update.
3. Create a team with `TeamCreate` to coordinate parallel exploration:
   ```
   TeamCreate({
     team_name: "project-docs-setup",
     description: "Analyze codebase and set up .claude/docs/ and .claude/rules/"
   })
   ```
4. Break the exploration into tasks using `TaskCreate` (one task per area):
   - Task 1: Project structure analysis
   - Task 2: Code architecture analysis
   - Task 3: Cross-cutting concerns analysis
5. Spawn three teammates in parallel via the `Agent` tool with `team_name: "project-docs-setup"`, assigning each a unique `name`. Use `subagent_type: "Explore"` (read-only — sufficient for research):
   - **`explorer-structure`**: Project structure — languages, frameworks, directory layout, entry points, build system, package managers, config files (.editorconfig, linter configs, etc.)
   - **`explorer-architecture`**: Code architecture — classes, modules, functions, API endpoints, data models, database schema, key patterns and conventions
   - **`explorer-concerns`**: Cross-cutting concerns — authentication, i18n, caching, error handling, testing setup, CI/CD, deployment
6. Assign tasks to each teammate via `TaskUpdate` with `owner: "<teammate-name>"`. Each teammate marks their task completed when finished and sends a summary back.
7. Focus on understanding **relationships and hidden contracts** that are not obvious from reading individual files.
8. When all teammates finish, send `{type: "shutdown_request"}` via `SendMessage` to each, then call `TeamDelete` before moving to Phase 2.

**Note**: If the project is small or the overhead of a team is unwarranted, you may skip team creation and use 1–3 plain parallel `Agent` calls with `subagent_type: "Explore"` instead.

**If the team tools are unavailable** (`TeamCreate` / `TaskCreate` / `TaskUpdate` / `SendMessage` are not in your toolset — Agent Teams is experimental and off unless `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set), do not stop and do not ask the user to enable it. Fall back to the same three explorations as plain parallel `Agent` calls with `subagent_type: "Explore"`, collect their reports yourself, and continue to Phase 2. Cloud sessions commonly land in this case.

---

## Phase 2: Create `.claude/docs/`

Create `mkdir -p .claude/docs/` and populate with reference documents.

### Required document

**`architecture.md`** — The entry point. Always created first. Contains:
- Doc selection guide (which doc to read for which task)
- Class/module index (name → file path → one-line purpose)
- API endpoint index (if applicable)
- Build system summary
- Key dependency list

### Additional documents (create based on project needs)

Choose from these based on what the project uses. Only create docs that are relevant:

| Document | Create when project has... |
|---|---|
| `data-model.md` | Database models, ORMs, custom post types, schemas |
| `i18n.md` | Internationalization/localization system |
| `api.md` | REST/GraphQL API endpoints |
| `auth.md` | Authentication/authorization system |
| `state-management.md` | Complex state (Redux, Vuex, etc.) |
| `testing.md` | Test infrastructure, fixtures, mocking patterns |
| `deployment.md` | CI/CD, deployment pipelines |
| `{feature}.md` | Any complex subsystem (e.g., gamification, payments, notifications) |

### Document format rules
- Optimized for Claude Code consumption, not human reading
- Use lookup tables, not prose paragraphs
- Use explicit file paths
- Each doc under 300 lines
- Focus on information NOT easily derivable from code: relationships, patterns, hidden contracts, resolution order, fallback chains
- English is acceptable
- Cross-reference other docs by filename

---

## Phase 3: Create `.claude/rules/`

Create `mkdir -p .claude/rules/` and populate with rule files.
Each rule file uses YAML frontmatter with `globs` to target specific file types.

### Required rules

**`read-docs.md`** — Read relevant docs before starting work:
```yaml
---
globs: [<project source file patterns>]
---
Before starting work, read `.claude/docs/architecture.md` to identify which additional docs are relevant, then read those docs.

<Include doc selection table from architecture.md>
```

**`update-docs.md`** — Update docs after completing work:
```yaml
---
globs: [<project source file patterns>]
---
After completing work, if your changes affect any pattern documented in `.claude/docs/`, update the relevant doc(s). Keep updates minimal and factual.

<List specific types of changes that require doc updates>
```

### Recommended rules (create based on project needs)

**`coding-standards.md`** — If the project has coding conventions:
- Check `.editorconfig`, linter configs (`.eslintrc`, `.prettierrc`, `phpcs.xml`, etc.)
- Ask the user about naming conventions, formatting preferences
- Include indentation, naming style, blank line rules

**`security.md`** — If the project handles user data, auth, or has security concerns:
- Sensitive endpoints or files not to modify
- Sanitization/validation requirements
- Auth/permission check requirements

**`build.md`** — If the project has a build system:
- Commands to run after modifying source files
- Cache busting / versioning steps

Set appropriate `globs` on each rule file so rules only apply when editing relevant files.

---

## Phase 4: Update CLAUDE.md

Add a brief reference section to `CLAUDE.md` pointing to the docs and rules:

```markdown
## Claude Code Reference Docs

Detailed technical reference documents in `.claude/docs/`. Rules for reading/updating these docs are in `.claude/rules/`.
```

Do NOT put detailed rules in CLAUDE.md — keep them in `.claude/rules/`.
CLAUDE.md should contain: project overview, development commands, architecture summary, and the reference to docs/rules.

---

## Phase 5: Summary

Report to the user:
1. List all files created in `.claude/docs/` with a one-line description of each
2. List all files created in `.claude/rules/` with a one-line description of each
3. Changes made to `CLAUDE.md`
4. Any recommendations for additional docs or rules the user might want to add later
5. Confirm that the `project-docs-setup` team (if created in Phase 1) has been shut down and deleted via `TeamDelete`
