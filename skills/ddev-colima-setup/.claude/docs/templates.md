# templates.md — the `templates/` directory

Rules that apply to every template, plus the per-file specifics that are not obvious
from reading the file alone. For placeholder mechanics see `generator.md`;
for *why* the values are what they are see `runtime-contracts.md`.

## Invariants for all templates

1. **No proper nouns.** Templates must contain zero project-, client-, or host-specific
   names. Anything project-specific becomes a placeholder.
2. **Placeholders must be registered** in `render()`'s `sed` in `scripts/generate.sh`.
3. **Templates are not executed from here.** `templates/*.sh` have no executable bit
   and are only valid after substitution; `bash -n` on them still works.
4. **Comments are Japanese and explanatory.** They survive into the user's repo and are
   the primary documentation the end user reads. A comment that states *why* (and the
   failure it prevents) is the norm — see `.claude/rules/coding-standards.md`.
5. **Self-referencing paths must use `__PROJECT_NAME__`**, because the generator writes
   several destinations with the project name embedded (`.ddev/mysql/<name>.cnf`,
   `.ddev/php/<name>.ini`) and the scripts and runbook look those paths up literally.
   The exception is the Colima profile: it is the fixed string `ddev` everywhere
   (`.colima/ddev.yaml`, `PROFILE="ddev"`), never `__PROJECT_NAME__`.

## Cross-file coupling

These references break silently if one side changes:

| Reference | From | To |
|---|---|---|
| `PROFILE="ddev"` | `colima-start.sh`, `colima-stop.sh`, `dev-up.sh` | `COLIMA_PROFILE` in `generate.sh` (destination of `colima.yaml` and the `.gitignore` line) |
| `${REPO_ROOT}/.colima/ddev.yaml` | `colima-start.sh` | destination of `colima.yaml` |
| `${REPO_ROOT}/scripts/colima-start.sh` | `dev-up.sh` | destination of `colima-start.sh` |
| `./scripts/colima-stop.sh` | `dev-down.sh`, `dev-up.sh`, `setup.md`, `migrate.md` | destination of `colima-stop.sh` |
| `~/.colima/_lima/colima-ddev` | `colima-start.sh` | Colima's own instance dir layout |
| `docker context use colima-ddev` | `colima-start.sh`, `setup.md`, `migrate.md` | context name Colima creates |
| `colima ssh --profile ddev -- ... /mnt/lima-colima-ddev` | `setup.md` | Colima's guest mount path for the profile |
| `__MAILPIT_HTTPS_PORT__` | `ddev-config.yaml`, `dev-up.sh` (fallback URL), `setup.md` | one value, three files — the fallback URL is wrong if they diverge |
| `mailpit_https_port` key name | `ddev-config.yaml` | parsed by `generate.sh`'s port collector out of *other* projects' configs |
| `ddev-__PROJECT_NAME__-{web,db}` | `setup.md` | container names DDEV derives from `name:` |
| `.ddev/mysql/zz-import.cnf{,.disabled}` | `setup.md` §4 | destination of `ddev-zz-import.cnf.disabled` |
| `xhprof_mode: prof` | `ddev-config.yaml` | explained in `setup.md` troubleshooting |
| `disable_settings_management` | `ddev-config.yaml` | procedure in `setup.md` §3 |

`setup.md` is the runbook the end user follows. **Any behavioral change to another
template must be reflected there**, or the user is following stale instructions.
`migrate.md` covers the one-time move off the old per-project-VM layout; a change to
what `--force` overwrites belongs there too.

## Per-file notes

### `colima.yaml`
Only top-level scalars are readable by `colima-start.sh`'s `yaml_get()` (a `yq`-free
awk extractor). It strips trailing `#` comments and surrounding quotes, and ignores
indented/nested values. Consequence: **`cpu`/`memory`/`disk`/`arch`/`vmType`/`mountType`/
`cpuType` must stay at column 0**. Nested keys (`network:`) are for the config file only
and never reach the first-run CLI flags.

### `colima-start.sh`
Two paths, branching on whether `~/.colima/_lima/colima-ddev` exists:
- **First run** — builds explicit `colima start` CLI flags from the template, because
  Colima v0.10.x does not read `~/.colima/<profile>/colima.yaml` on the creation run and
  would otherwise create a 2-core/2 GiB VM. Missing values abort with the key names.
- **Later runs** — branch on the **exit code** of `colima status` (0 = running), else
  `colima start --profile`, then `warn_resource_drift()`. Do not switch this back to a string
  grep: the status message is lowercase (`is running` / `is not running`) and `Running` only
  appears in `colima list`, so a `grep -q "Running"` never matches and the "already up, skip"
  path becomes unreachable.

`warn_resource_drift()` exists because the second and later projects never create the VM,
so their `.colima/ddev.yaml` edits silently do nothing. It parses `colima list --json`
with `perl` (no `jq` dependency), compares cpu / memory / disk against `yaml_get`, and
prints the differences on stderr. It **never recreates the VM** (that would destroy every
project's database) and returns 0 on any parsing failure — a broken warning must not block
startup. The caller wraps it in `set +e` / `set -e` for the same reason.

Always ends with `docker context use colima-ddev`.

### `dev-up.sh` / `colima-stop.sh`
Both carry an identical `probe_colima()` implementing a timeout by hand (macOS has no
`timeout(1)`): background the status call, poll `kill -0`, `kill -TERM` past
`COLIMA_PROBE_TIMEOUT=25`, and `wait` to suppress the shell's "Terminated" notice.
Return codes are **`0=Running / 1=not running / 2=hung`** in both files, but the
reaction differs: `dev-up` treats a hang as fatal with recovery instructions
(colima issue #460, sleep/wake hang); `colima-stop` escalates to `colima stop --force`.
Keep the two copies in sync when editing either. (`dev-down.sh` no longer has a copy —
it does not touch the VM at all.)

`dev-up.sh` waits for actual HTTP 2xx/3xx (`wait_for_http`, 180 s) before opening the
browser — container health is not the same as the site answering. A 3xx counts as
success because login-gated apps redirect when unauthenticated. Browser URLs are opened
last-wins so the main site ends up the active tab. The Mailpit URL comes from
`ddev describe -j` (parsed with `perl`, no `jq`) and falls back to
`https://__FQDN__:__MAILPIT_HTTPS_PORT__` — a failed lookup must not stop the browser
from opening. A `colima status` hang is fatal, and the printed recovery command carries
an explicit note that its `ddev poweroff` stops **every** project.

### `colima-stop.sh` / `dev-down.sh` — the stop split
`dev-down.sh` runs `ddev stop` only: the VM is shared, so `ddev poweroff` + `colima stop`
would interrupt other people's projects. `colima-stop.sh` is the deliberate
"stop everything" path and says so in its header, its first message, and `setup.md`.

Both are non-destructive. **`colima delete` must never appear in either** — on a shared VM
it destroys the named volumes of *all* projects, not just this one. It belongs only in
`migrate.md`'s final teardown step, behind explicit preconditions.

### `ddev-config.yaml`
The one template with a mandatory post-generation edit by the user; see
`runtime-contracts.md` for `disable_settings_management` and `xhprof_mode`.
Holds the `__ADDITIONAL_FQDNS_BLOCK__` line, which must remain alone at column 0.

Port keys split into two kinds: `router_http_port` / `router_https_port` are **the same in
every project** (one Traefik owns 80/443 and routes by Host header), while
`mailpit_http_port` / `mailpit_https_port` are **unique per project** because Mailpit binds
host ports directly. Making the router ports per-project would give up the clean URL;
making the Mailpit ports shared breaks `ddev start` on the second project.

### `migrate.md`
A one-time runbook, not part of the normal flow. Its ordering is the content: DB export
first, destructive teardown (`colima delete` of the old profile) last and behind a
precondition checklist, because with several projects on the old layout the old VM must
survive until the final one is verified on the shared VM. It ends with a step to delete or
secure the dumps — they hold production-like personal data.

### `ddev-mysql.cnf` / `ddev-zz-import.cnf.disabled`
DDEV mounts `.ddev/mysql/*.cnf` into `/etc/mysql/conf.d/`, read in alphabetical order,
last writer wins. The `zz-` prefix is what lets the import file override the always-on
file. The `.disabled` suffix makes enablement a rename rather than a comment edit, so a
forgotten re-disable is visible in `git status`. Do not put SESSION-only variables
(`unique_checks`, `foreign_key_checks`) under `[mysqld]` — MariaDB aborts with
"unknown variable" (exit 7); mysqldump output already sets them per session.

### `ddev-php.ini`
`mbstring.internal_encoding` / `http_input` / `http_output` are deprecated in PHP 8.2+
and are intentionally absent; `default_charset` / `internal_encoding` replace them.

### `Brewfile`
`docker-buildx` is required by DDEV v1.25.1+. Homebrew installs it outside Docker's
plugin path, so `setup.md` §1 symlinks it (and `docker-compose`) into
`~/.docker/cli-plugins/`; without that, `ddev start` fails with "buildx ... not found".
`nss` exists only so `mkcert` can trust certs in Firefox.
