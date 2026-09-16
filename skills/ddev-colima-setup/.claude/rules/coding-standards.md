---
globs: ["scripts/**", "templates/*.sh", "templates/*.yaml", "templates/*.cnf", "templates/*.ini", "templates/*.disabled", "templates/Brewfile"]
---
No linter or `.editorconfig` exists in this repo. Match the surrounding files.

## Shell
- `#!/usr/bin/env bash` then `set -euo pipefail`.
- 2-space indent. Quote every expansion (`"${VAR}"`); braces on variables inside strings.
- Resolve the repo root as `REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`.
- Prefix user-facing output with the script name: `echo "[dev-up] ..."`. Errors and
  warnings go to stderr (`>&2`).
- Around a command whose non-zero exit is expected, wrap with `set +e` / `set -e` and
  capture `$?` immediately — do not rely on `||` swallowing it.
- Do not assume GNU userland: macOS has no `timeout(1)` and BSD `sed`/`awk` semantics
  apply. Prefer awk/perl over GNU-only sed flags.
- Section headers use the existing form: `# --- 見出し ---`.

## Comments
- Japanese, explanatory, stating **why** and the failure the code prevents — not what
  the line does. This is the dominant convention and template comments ship to the end
  user as their documentation.
- Keep the emphasis markers already in use (`★★★ 重要 ★★★`, `絶対 ON にしないこと`,
  `戻し忘れ厳禁`) when editing those blocks; they mark data-loss and privacy hazards.
- Reference upstream issues by number where one exists (e.g. `colima #460`).

## Config templates
- Align `=` / `:` values within a block, as the existing files do.
- Every non-obvious value carries a trailing comment with its rationale.
- Placeholders are `__UPPER_SNAKE__` and must be registered in `render()`'s `sed`.

## Commit messages
`[<verb>]<scope>: <日本語の要約>` — e.g. `[fix]ddev-colima-setup: xhgui を完全に無効化する`.
Verbs in use: `add`, `up`, `fix`.
