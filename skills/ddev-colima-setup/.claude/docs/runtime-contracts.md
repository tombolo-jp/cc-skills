# runtime-contracts.md — ordering rules and irreversible operations

Constraints of the *generated* environment. Every item here was learned from a real
failure; changing a value without understanding the rule reintroduces the failure.

## Irreversible / destructive operations

| Operation | Consequence | Guard |
|---|---|---|
| `colima delete --profile ddev` | Destroys the shared VM. **Every** project's DB lives in named volumes on it — treat as data loss across the whole host, not one project. | Never emit it from any generated script. `setup.md` mentions it only in a warning; `migrate.md` uses it solely to remove the *old* per-project profile, behind a precondition checklist. |
| Changing `vmType` / `mountType` / `arch` in `.colima/ddev.yaml` after first start | Colima cannot apply these to an existing VM; applying them means delete + recreate — losing every project at once. | Fixed values (`vz` / `virtiofs` / `aarch64`) with a warning comment at the top of `colima.yaml`. |
| `rm -rf /var/lib/docker/{containers,volumes/metadata.db}` (the "Recreate / No such container" fix) | Wipes volume metadata → DB data gone **for all projects on the shared VM**. | `setup.md` restricts it to *before* DB import and warns not to run it once another project is built. |
| `ddev poweroff` (including inside the colima #460 recovery command) | Stops every project and the router, not just the current one. | `dev-down.sh` uses `ddev stop` instead; `colima-stop.sh` and the recovery messages state the scope explicitly. |
| `general_log = 1` in `ddev-mysql.cnf` | Logs every SQL statement including personal data in WHERE clauses. | Pinned to `0` with an explicit "絶対 ON にしないこと" comment. |

## `disable_settings_management` — ordering matters

Generated as **`false`**, and that is deliberate.

1. First `ddev start` with `false` → DDEV writes `wp-config-ddev.php` and, for a
   DDEV-managed `wp-config.php`, appends the `require_once` line.
2. User verifies the file and the require line exist.
3. User flips to `true` and `ddev restart`, so DDEV stops rewriting `wp-config.php`.

Setting `true` from the start means no `wp-config-ddev.php`, therefore no `DB_*`
constants, therefore WordPress cannot reach the database. Recovery is to flip back to
`false`, restart, confirm generation, flip forward.

Two user-facing cases, both in `setup.md` §3:
- **Clean WP** — DDEV inserts the `require_once` automatically; verify only.
- **User-managed `wp-config.php`** (log line: `An existing user-managed wp-config.php
  file has been detected!`) — DDEV inserts nothing. The user must add the `require_once`
  *before* the DB defines and convert existing defines to `defined() || define()`,
  otherwise the earlier defines win and DDEV's become no-ops. `wp-config-ddev.php`
  returns early when `IS_DDEV_PROJECT` is unset, so the same file still works on Local.

## `xhprof_mode: prof` — not the default

DDEV's default `xhgui` mode accumulates profile results into MariaDB without bound.
Observed: `xhgui/results.ibd` reached 85 GB, filled the VM disk, and left the web
container unable to start (`No space left on device`). `prof` writes files only.
Do not change this default; profile on demand with `ddev xhprof on`.

## Disk exhaustion recovery (two steps, both required)

Dropping the database inside the VM does **not** shrink the host disk image. The
sparse image only releases space after a trim:

```bash
docker builder prune -af
docker exec ddev-<name>-db mariadb -uroot -proot -e "DROP DATABASE IF EXISTS xhgui;"
colima ssh --profile ddev -- sudo fstrim -av       # observed 92GB → 8.5GB
```

On the shared VM one project's runaway growth stops **every** project, and the recovery
window is downtime for all of them. `setup.md` therefore promotes periodic usage checks
(`df -h /mnt/lima-colima-ddev`, `du -sh ~/.colima/_lima/_disks/colima-ddev/`) from a
recovery-only command to a standing operational step. `disk: 80` is also deliberately not
larger: an oversized sparse disk delays the first symptom until far more space is gone.

## Bulk DB import cycle

`.ddev/mysql/zz-import.cnf.disabled` trades crash safety for throughput
(`innodb_doublewrite=0`, `innodb_flush_log_at_trx_commit=0`). It is enabled by rename +
`ddev restart`, and **must be renamed back** + `ddev restart` after the import. Leaving
it on means an unclean shutdown can corrupt InnoDB. `setup.md` §4 marks this
"戻し忘れ厳禁"; keep that emphasis in any rewrite.

## Memory budget — sized for the whole shared VM, not one project

`innodb_buffer_pool_size` (`ddev-mysql.cnf`) is allocated inside the VM whose ceiling is
`memory` in `colima.yaml`. On the shared VM **three projects' worth** of db + web
containers must fit at once, so the budget is an accumulation, not a single figure:

| Item | Subtotal |
|---|---|
| db × 3 (`innodb_buffer_pool_size` 512M + other InnoDB/connection buffers ≒ 500M) | ~3.0 GiB |
| web × 3 (nginx + PHP-FPM) | ~3.0 GiB |
| Traefik router + ssh-agent + Mailpit × 3 | ~0.4 GiB |
| Guest OS + dockerd | ~1.0 GiB |
| **Total** | **~7.4 GiB → `memory: 8`** |

Current defaults: `innodb_buffer_pool_size` `512M`, `memory` `8` GiB, `cpu` `4`,
`disk` `80` GiB. `cpu` is *not* multiplied by project count — cores are time-shared, so it
tracks the heaviest single workload (`composer install`, builds) rather than the sum.

`generate.sh` warns when `pool × 3` exceeds 50% of VM memory. The `× 3` matters: the
old per-project check passed values that OOM-kill db containers once a second project
starts. `--innodb-buffer-pool` remains per-project so a genuinely large DB can be raised
individually — the warning is the guard against doing that blindly.

PHP is sized the same way: `memory_limit 512M` and `opcache.memory_consumption 128` are
per-project figures multiplied by concurrent projects.

The always-on config deliberately caches the working set of a standard-sized WordPress DB
and turns `performance_schema` off to save memory. Session buffers (`sort_buffer_size`,
`read_buffer_size`, `read_rnd_buffer_size`, `join_buffer_size`) are allocated **per
connection**, so they scale with connections × projects — that is why they are the most
aggressively reduced values. `innodb_flush_log_at_trx_commit = 2` is a development-machine
choice (production wants `1`) and the comment says so.

## Clean HTTPS URL — and why the VM must be shared

`router_http_port: "80"` + `router_https_port: "443"` + `project_tld: <tld>` +
`use_dns_when_possible: false` produce `https://<fqdn>` with no port, resolved through
`/etc/hosts` (DDEV writes the entry, prompting for sudo once). `mkcert -install` supplies
the trusted CA — a certificate warning means it was skipped or the browser was not restarted.

macOS has exactly one port 443, and DDEV runs exactly one Traefik router per Docker host.
Two Colima VMs therefore cannot both serve clean URLs, and `docker context` is global to
the host, so the second VM's projects are simply invisible to `ddev`. Hence one host-wide
profile, `ddev`, hard-coded rather than configurable: a per-project profile name is the
exact input that reintroduces the conflict.

## Mailpit ports — per project, unlike the router

Traefik multiplexes 80/443 by Host header, so router ports stay identical everywhere.
Mailpit binds host ports directly and cannot be shared: `mailpit_http_port` /
`mailpit_https_port` must differ per project or the second `ddev start` fails on a port
conflict. `generate.sh` assigns them from `8026` (HTTPS; HTTP is one below) in steps of 2,
skipping values already used by known projects.

Collection reads `~/.ddev/project_list.yaml` and each listed project's `.ddev/config.yaml`
as **files**; the `ddev` binary is never invoked, preserving the generator's property of
working on a machine without DDEV installed. When the list is unreadable the start value is
used with a stderr warning — a wrong port surfaces immediately as a failed `ddev start`,
whereas a hard failure here would block generation on machines that have no DDEV at all.

## Known upstream issues encoded in the templates

| Issue | Symptom | Handling |
|---|---|---|
| colima #460 | `colima status` hangs after macOS sleep/wake | `probe_colima()` timeout in `dev-up.sh` / `colima-stop.sh`; recovery command printed, annotated that its `ddev poweroff` stops all projects |
| colima v0.10.x | `~/.colima/<profile>/colima.yaml` ignored on VM creation → 2 core / 2 GiB VM | `colima-start.sh` builds explicit CLI flags on first run |
| DDEV v1.25.1+ | `buildx ... not found` | `Brewfile` installs `docker-buildx`; `setup.md` §1 symlinks it into `~/.docker/cli-plugins/` |
| Colima data disk persistence | `ddev start` fails with `Recreate / No such container` after `colima delete` | docker-state reset procedure in `setup.md`, gated to before DB import and to a host with no other project built |
| `colima delete` leaves the data disk | Deleting the old per-project VMs frees no space — the disks stay under `~/.colima/_lima/_disks/` (9 of them held 83 GiB after a real migration), and the orphans later feed the `Recreate` failure above | `migrate.md` §8 requires `limactl disk delete` on the orphaned disks after `colima delete`, checked against `limactl disk ls` (`IN-USE-BY` empty) and `df` |
| Colima config read on creation only | `.colima/ddev.yaml` edits after the VM exists silently do nothing — the second project's values never apply, and neither does a later edit in the first project | `warn_resource_drift()` in `colima-start.sh` reports the difference instead of recreating the VM; `setup.md` documents the colima-side change (`colima start --profile ddev --cpu N --memory N`, or `--edit`), the follow-up edit of the repo file, and that `disk` can only grow |
| `colima status` message casing | The status text is lowercase (`is running` / `is not running`); `Running` appears only in `colima list` | `colima-start.sh` branches on the **exit code** of `colima status`, never on its text. Do not reintroduce a string grep |
| Mailpit host-port conflict | Second project's `ddev start` fails binding the Mailpit port | Per-project assignment in `generate.sh` (+2 steps) and a troubleshooting row in `setup.md` |
| `project_list.yaml` lists a project only once it has been started | Two projects generated back to back both take the default 8026, and the second `ddev start` fails on the port — the generator cannot see a project that has never run | `generate.sh` also rejects ports currently being listened on (`lsof`), which covers the case where the first project is running; `SKILL.md` step 6 and a `setup.md` row tell the user to start each project before generating the next, or to pass `--mailpit-port` |
| Stale generated `dev-down.sh` | An old copy still runs `ddev poweroff` + `colima stop`, killing every project | `setup.md` troubleshooting row tells the user to regenerate; `migrate.md` lists the file among what `--force` replaces |
| `ddev export-db` defaults to one database | A project whose second site uses its own database (a `wp-config.php` that pins `DB_NAME` instead of loading `wp-config-ddev.php`) migrates with that data missing — the site fails with "Error establishing a database connection", and the loss is unrecoverable once the old VM is deleted | `migrate.md` §1 requires `show databases` before the old VM is stopped, and `--database=<name>` on both export and import; §6's checks include sub-directory sites |
| DDEV-generated `.ddev/.gitignore` | It excludes `/config.local.y*ml` and `/config.*.local.y*ml`, so per-project overrides written to `config.local.yaml` are silently untracked and never reach the rest of the team | `migrate.md` §3 directs overrides to `.ddev/config.project.yaml`, which DDEV merges the same way but the generated ignore list does not match |

### Overrides survive `--force` only outside `config.yaml`

**Not verified against a running DDEV yet** — unlike the rows above, the merge behaviour below is
read from DDEV's documented contract, not from an observed failure. Confirm it with
`ddev debug configyaml` (needs a running Docker daemon) and record the DDEV version here.

`--force` replaces `.ddev/config.yaml` wholesale, so any setting beyond the template
(`docroot`, `database`, `upload_dirs`, `webimage_extra_packages`, `web_environment`, `hooks`)
must live in `.ddev/config.project.yaml`; DDEV merges `config.yaml` and `config.*.yaml` in
filename order. Write list values as a **complete** list there — the result is then the same
whether DDEV overwrites or appends, so the setup does not depend on that behaviour.
`ddev debug configyaml` prints the merged values, but needs a running Docker daemon.
