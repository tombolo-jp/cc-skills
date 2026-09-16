---
globs: ["templates/**", "scripts/generate.sh"]
---
This skill writes files into other people's repositories and generates commands they
will run against a VM holding their database.

- **Placeholders are a two-place edit.** A `__TOKEN__` added to a template must also be
  added to the `sed` in `render()` (`scripts/generate.sh`), or it ships literally into
  the user's repo. After any template change, verify: run the generator against a
  scratch `--target` and confirm
  `grep -rn '__[A-Z_]*__' <target> | grep -v '__DIR__'` returns nothing
  (`__DIR__` is a PHP magic constant in `setup.md`'s code samples, not a placeholder).
- **`__ADDITIONAL_FQDNS_BLOCK__` must stay alone on its own line at column 0.**
  It is handled by `fqdn_block()`, not by `sed`; indenting it breaks both branches.
- **No proper nouns in templates.** No project, client, host, or personal names.
- **Preserve non-destructive defaults.** `render()` skips existing files unless
  `--force`; the `.gitignore` append stays idempotent (`grep -qxF`).
- **Never emit a destructive command into a routine path.** `colima delete`,
  `docker volume rm`, `rm -rf /var/lib/docker/*`, and `DROP DATABASE` on the project DB
  must not appear in `dev-up.sh` / `dev-down.sh` / `colima-start.sh`. They belong only in
  `templates/setup.md` recovery sections, with an explicit precondition
  (e.g. "before DB import only") stated inline.
- **Never enable `general_log`** in `ddev-mysql.cnf`: it records personal data from
  WHERE clauses.
- **Do not remove the emphasized warnings** on `disable_settings_management`,
  `zz-import.cnf`, or the Colima immutable keys (`vmType` / `mountType` / `arch`).
  Each prevents a documented data-loss or connectivity failure — see
  `.claude/docs/runtime-contracts.md`.
- **Do not put SESSION-only MariaDB variables under `[mysqld]`** (`unique_checks`,
  `foreign_key_checks`): the server aborts at startup with exit 7.
- Templates are never executed from this repo. Check them with `bash -n` and by
  generating into a scratch directory — never by running `templates/*.sh` in place.
