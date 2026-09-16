# Architecture — ddev-colima-setup

A Claude Code **skill** (not an application). It renders a set of static templates
into a target repository, substituting `__PLACEHOLDER__` tokens with per-project values.
There is no runtime, no build step, no test suite, and no dependency manifest.

## Doc selection guide

| Task | Read |
|---|---|
| Change how files are generated / add a CLI flag / add a placeholder | `generator.md` |
| Edit any file under `templates/` | `templates.md` (+ `generator.md` for the placeholder contract) |
| Change Colima VM settings, DDEV config, MariaDB/PHP tuning | `runtime-contracts.md` |
| Change the generated setup doc (`templates/setup.md`) | `runtime-contracts.md` |
| Change the skill's invocation surface (args, steps, description) | `SKILL.md` + `generator.md` |

## File index

| File | Purpose |
|---|---|
| `SKILL.md` | Skill frontmatter (`name`/`description`/`argument-hint`/`allowed-tools`) + the procedure Claude follows. Documents inputs and design rationale. |
| `scripts/generate.sh` | The entire generator. Arg parsing → validation → placeholder substitution → write → chmod → `.gitignore` append. |
| `templates/Brewfile` | Host-side Homebrew deps (colima, lima, docker CLI trio, ddev, mkcert, nss). |
| `templates/colima.yaml` | Shared Colima VM profile (`ddev`), identical in every project. Contains immutable-after-creation keys. |
| `templates/colima-start.sh` | First-run VM creation via explicit CLI flags; subsequent runs reuse the VM and warn on resource drift. |
| `templates/colima-stop.sh` | Shared-VM shutdown: `ddev poweroff` → `colima stop` (stops **every** project). |
| `templates/dev-up.sh` | One-command start: colima → `ddev start` → HTTP readiness poll → open browser. |
| `templates/dev-down.sh` | Per-project shutdown: `ddev stop` only. Does not touch the VM. |
| `templates/ddev-config.yaml` | DDEV project config (WordPress, clean HTTPS URL, xhprof, settings management). |
| `templates/ddev-mysql.cnf` | Always-on MariaDB tuning. |
| `templates/ddev-zz-import.cnf.disabled` | Temporary bulk-import I/O tuning; enabled by renaming. |
| `templates/ddev-php.ini` | PHP overrides (limits, charset, opcache). |
| `templates/setup.md` | The setup runbook emitted into the target repo. |
| `templates/migrate.md` | One-time runbook for moving a per-project VM setup onto the shared VM. |

There is no `tests/`, no CI config, and no package manifest. Verification is manual
(`bash -n`, then a real `generate.sh` run against a scratch `--target`).

## Data flow

```
user args ──▶ scripts/generate.sh
                 │  defaults, required-arg check
                 │  PROJECT_NAME derivation (basename → sanitize)
                 │  FQDN split → FQDN_HOST / PROJECT_TLD
                 │  NEED_ADDITIONAL_FQDNS = (FQDN_HOST != PROJECT_NAME)
                 │  --mailpit-port validation (numeric, 1024–65535)
                 │  Mailpit port assignment: read ~/.ddev/project_list.yaml →
                 │    each project's .ddev/config.yaml, plus lsof LISTEN check
                 │    → bump by 2 until free
                 │  sanity warn: innodb pool × 3 > 50% of shared VM memory
                 ▼
            render() per template
                 sed (11 placeholders) │ fqdn_block() ──▶ $TARGET/<dest>
                 ▼
            chmod +x scripts/*.sh (4 scripts)
            append .colima/ddev.local.yaml to .gitignore (idempotent)
```

## Placeholder index

Every token below is substituted by the single `sed` invocation in `render()`
(`scripts/generate.sh`). A token used in a template but absent from that `sed` list
ships literally into the generated file — see `generator.md`.

| Placeholder | Source | Example |
|---|---|---|
| `__PROJECT_NAME__` | `--name`, else sanitized `basename $TARGET` | `myapp` |
| `__PHP_VERSION__` | `--php` (required) | `8.3` |
| `__MARIADB_VERSION__` | `--mariadb` (required) | `11.4` |
| `__FQDN__` | `--fqdn` (required) | `myapp.local` |
| `__PROJECT_TLD__` | derived: `${FQDN#*.}` | `local` |
| `__COLIMA_CPU__` | fixed constant (no flag) | `4` |
| `__COLIMA_MEMORY__` | fixed constant (no flag), GiB | `8` |
| `__COLIMA_DISK__` | fixed constant (no flag), GiB | `80` |
| `__INNODB_BUFFER_POOL__` | `--innodb-buffer-pool` (default `512M`) | `512M` |
| `__MAILPIT_HTTP_PORT__` | derived: `__MAILPIT_HTTPS_PORT__ - 1` | `8025` |
| `__MAILPIT_HTTPS_PORT__` | `--mailpit-port` (default `8026`), bumped by 2 until free of both known projects and host listeners | `8026` |
| `__ADDITIONAL_FQDNS_BLOCK__` | line-level; expanded or deleted by `fqdn_block()`, **not** by `sed` | see `generator.md` |

## Key dependencies

Host tools the generated environment needs (declared in `templates/Brewfile`):
`colima`, `lima`, `docker`, `docker-buildx`, `docker-compose`, `ddev/ddev/ddev`, `mkcert`, `nss`.

The generator itself needs only: `bash`, `sed`, `awk`, `perl`, `grep`, `tr`, `chmod`.
`perl` is used only inside `fqdn_block()` for the multi-line substitution.

## Platform assumption

macOS on Apple Silicon, hard-coded: `arch: aarch64`, `vmType: vz`, `mountType: virtiofs`,
`open(1)` for browsers, and hand-rolled timeouts because macOS lacks `timeout(1)`.

## Shared-VM model

All generated projects target one host-wide Colima profile named `ddev` (a fixed string,
deliberately not a flag or a placeholder — a per-project value would let two projects
create two VMs and break the scheme). Consequences that shape several files:

- The VM is created by whichever project starts first; later projects reuse it, so
  `.colima/ddev.yaml` edits made after creation do not take effect. `colima-start.sh`
  reports the drift instead of recreating the VM.
- Stopping is two-tiered: `dev-down.sh` (this project) vs `colima-stop.sh` (everything).
- Router ports 80/443 are shared via Host-header routing; Mailpit binds host ports
  directly and therefore needs a distinct pair per project.
- Disk exhaustion and VM failure affect every project at once.
