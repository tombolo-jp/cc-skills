# generator.md — `scripts/generate.sh`

The whole generator. Read this before adding a flag, a placeholder, or a template.

## Contracts you must not break

### 1. Placeholder registration is a two-place edit
Adding `__NEW_TOKEN__` to a template does nothing on its own. It must also be added
as a `-e "s|__NEW_TOKEN__|${VAL}|g"` line to the single `sed` in `render()`.
Unregistered tokens are written verbatim into the user's repo with no warning.
Use `|` as the sed delimiter (values contain `/` in paths and URLs).

### 2. `__ADDITIONAL_FQDNS_BLOCK__` is line-level, not inline
It is handled by `fqdn_block()`, a stdin filter applied after `sed`:

| Condition | Behavior |
|---|---|
| `FQDN_HOST != PROJECT_NAME` | `perl -pe` replaces the whole line with `additional_fqdns:\n  - <FQDN>` |
| `FQDN_HOST == PROJECT_NAME` | `grep -v` deletes the line entirely |

Both branches anchor on `^__ADDITIONAL_FQDNS_BLOCK__$`. The token must therefore sit
**alone on its own line at column 0** — indenting it or putting text beside it silently
breaks both branches. Currently used only by `templates/ddev-config.yaml`.

Rationale: DDEV's canonical URL is `<name>.<tld>`. Only when the requested FQDN's host
label differs does an explicit `additional_fqdns` entry become necessary.

### 3. Non-destructive by default
`render()` skips any existing destination unless `--force`. Preserve this: the generator
runs against real project repos. The `.gitignore` append is guarded by `grep -qxF` so
repeated runs do not duplicate the entry.

### 4. The shared Colima profile name is a fixed constant
`COLIMA_PROFILE="ddev"` in `generate.sh`, and hard-coded as `PROFILE="ddev"` in
`colima-start.sh` / `colima-stop.sh` / `dev-up.sh`. It is deliberately **not** a flag and
**not** a placeholder: the shared-VM scheme only holds while every project points at the
same name, so a per-project value would be the failure mode rather than a feature.
Changing it means editing the generator and all three scripts together.

### 5. `usage()` reads the file's own header
`usage()` is an `awk` pass over lines 2–30 that strips the leading `# ` and **stops at the
first non-comment line**. **The flag documentation lives in the comment block starting at
line 2.** Adding a flag without updating that block leaves `--help` wrong; growing the
block past line 30 truncates the help output. Keep the block and the `case` arms in sync,
and mirror the change in `SKILL.md`'s input tables.

The stop-at-first-non-comment rule matters: a plain `sed -n '2,30p'` also prints whatever
shell code follows a shorter header, and later `# --- section ---` comments inside that
range, both of which end up in `--help`.

## Derived values

| Value | Derivation | Failure mode |
|---|---|---|
| `PROJECT_NAME` | `--name` when given, else `basename $TARGET`; either way through `sanitize_name()`: lowercase → `[^a-z0-9-]`→`-` → collapse `--` → strip leading/trailing `-` | Empty result exits 2 asking for `--name` |
| `FQDN_HOST` | `${FQDN%%.*}` | — |
| `PROJECT_TLD` | `${FQDN#*.}` | If FQDN has no dot, exits 2 |
| `TARGET` | `cd "$TARGET" && pwd` (absolute) | Non-existent dir fails here |
| `MAILPIT_HTTPS_PORT` | `--mailpit-port` (default `8026`), bumped `+2` while the value appears among known projects' `mailpit_https_port` **or is being listened on** (`lsof`) | Scan span exhausted (`start+40`) or `>65535` → warn, fall back to the start value |
| `MAILPIT_HTTP_PORT` | `MAILPIT_HTTPS_PORT - 1` | — |

## Flags

| Flag | Required | Default |
|---|---|---|
| `--php <ver>` | yes | — |
| `--mariadb <ver>` | yes | — |
| `--fqdn <host.tld>` | yes | — |
| `--target <dir>` | | cwd |
| `--name <name>` | | sanitized `basename $TARGET` |
| `--mailpit-port <n>` | | `8026` (HTTPS side; HTTP is `n-1`) |
| `--innodb-buffer-pool <size>` | | `512M` |
| `--setup-doc <path>` | | `.claude/tasks/docker/setup.md` |
| `--force` | | off (existing files are skipped) |

`--cpu` / `--memory` / `--disk` were **removed**. They now fall through to the unknown-arg
branch and exit 2. Shared-VM resources are fixed constants in the script
(`COLIMA_CPU=4` / `COLIMA_MEMORY=8` / `COLIMA_DISK=80`). Changing an already-created VM is a
colima-side operation (`colima start --profile ddev --cpu N --memory N`); editing
`.colima/ddev.yaml` alone does nothing, since colima reads its own saved config. The generated
file is the first-run source and the drift-warning baseline — `setup.md` documents both steps.

## Validation and warnings

- **Required**: `--php`, `--mariadb`, `--fqdn`. Missing ones are collected and reported together, exit 2.
- **`--name` normalization (non-fatal)**: an explicitly given `--name` goes through the same
  `sanitize_name()` as the derived one, and a difference is reported on stderr; an empty result
  exits 2. `PROJECT_NAME` is both a `sed` replacement value and part of the output paths
  (`.ddev/mysql/<name>.cnf`), so sanitizing keeps `|` (the sed delimiter) and `../` out of both.
- **`--mailpit-port` (fatal)**: non-numeric, or outside `1025–65535`, exits 2. The lower bound is
  1025, not 1024, because the HTTP port is derived as `n-1` — allowing 1024 would emit a
  privileged 1023 and defeat the check.
- **Mailpit port collection (non-fatal)**: reads `~/.ddev/project_list.yaml`, then each
  listed project's `.ddev/config.yaml`, for `mailpit_https_port`. The target's own approot
  is excluded so regeneration does not bump the project past its own port. The `ddev`
  binary is never invoked — the generator must keep working on a machine without DDEV.
  Unreadable list → warn on stderr and fall back to the listener check alone (below).
- **Mailpit listener check (non-fatal)**: `port_listening()` additionally rejects a candidate
  that something on the host is already listening on
  (`lsof -nP -iTCP:<port> -sTCP:LISTEN`), printing which port it skipped. The two sources are
  complements, and neither alone is sufficient: the project list sees a **stopped** project's
  reservation but not a non-DDEV process, while `lsof` sees only what is **listening right now**.
  `lsof` absent → the check is skipped (`command -v` guard), preserving the no-external-command
  property; the list scan still applies. Because the bump loop now runs whether or not the list
  was readable, a machine with no `project_list.yaml` still avoids the ports of running projects.
- **Sanity warning (non-fatal)**: an `awk` block normalizes `--innodb-buffer-pool`
  (`G`/`M`/`K`/bare bytes) to MiB and warns on stderr if **three times** that value
  (three projects sharing one VM) exceeds 50% of the fixed VM memory. Rationale: MariaDB
  mmaps the pool at container start; over-provisioning OOM-kills the db containers. The awk
  returns empty for unparsable input, which disables the check rather than failing.

## Template → destination map

| Template | Destination (relative to `--target`) |
|---|---|
| `Brewfile` | `Brewfile` |
| `colima.yaml` | `.colima/ddev.yaml` (shared profile name, **not** `<name>`) |
| `colima-start.sh` | `scripts/colima-start.sh` |
| `colima-stop.sh` | `scripts/colima-stop.sh` |
| `dev-up.sh` | `scripts/dev-up.sh` |
| `dev-down.sh` | `scripts/dev-down.sh` |
| `ddev-config.yaml` | `.ddev/config.yaml` |
| `ddev-mysql.cnf` | `.ddev/mysql/<name>.cnf` |
| `ddev-zz-import.cnf.disabled` | `.ddev/mysql/zz-import.cnf.disabled` |
| `ddev-php.ini` | `.ddev/php/<name>.ini` |
| `setup.md` | `$SETUP_DOC` (default `.claude/tasks/docker/setup.md`) |
| `migrate.md` | `$(dirname $SETUP_DOC)/migrate.md` |

Adding a template = add the file under `templates/` **and** a `render` line in the
generation block. Destinations containing `<name>` must use `${PROJECT_NAME}` so the
generated file matches what `colima-start.sh` / `setup.md` reference by path.

## Post-generation side effects

1. `chmod +x` on `scripts/{colima-start,colima-stop,dev-up,dev-down}.sh` — the sed pipeline drops the mode bit.
2. Appends `.colima/ddev.local.yaml` to `$TARGET/.gitignore` (creating it if absent),
   with a Japanese comment explaining that only the team-standard profile is committed.
   The `.local.yaml` file itself is never generated; it is a convention for per-developer overrides.

## Verifying a change

No test suite exists. The expected loop:

```bash
bash -n scripts/generate.sh
d=$(mktemp -d) && bash scripts/generate.sh --php 8.3 --mariadb 11.4 --fqdn myapp.local --target "$d"
grep -rn '__[A-Z_]*__' "$d" | grep -v '__DIR__'   # must return nothing
```

`__DIR__` is excluded because it is a PHP magic constant inside `setup.md`'s
`wp-config.php` code samples, not a generator placeholder.

Also run once with an FQDN host matching the target dir name to exercise the
`fqdn_block()` deletion branch, and once with `--cpu 8` to confirm the removed flags
exit 2. Generating into two different `--target` directories in a row exercises the
Mailpit bump (on a machine where `~/.ddev/project_list.yaml` is readable).
