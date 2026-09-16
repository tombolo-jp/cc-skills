#!/usr/bin/env bash
# ゲート自己検証 — 「そのゲートは、既知の非互換を実際に検出できるか」を能動的に確かめる
#
# 使い方:
#   scripts/verify-gate.sh --gate=phpstan   --plant-dir=wp-content/themes/mytheme [--config=phpstan.neon]
#   scripts/verify-gate.sh --gate=phpcompat --plant-dir=wp-content/themes/mytheme --testversion=8.3
#   scripts/verify-gate.sh --gate=logger    --logger=scripts/php-migration-logger.php \
#                          --log=/tmp/probe.log --php-bin=/path/to/php
#
# 前提: 対象ゲートのツールが導入済みであること。`--plant-dir` は**解析対象スコープ内**であること。
#
# ★★ 稼働中の本番ドキュメントルートに対して実行しないこと。★★
#   本スクリプトは削除済み API を含む `.php` を一時的に設置する。
#   Web から到達できる場所に置くと、その間だけ HTTP で直接実行されうる。
#   検証はローカル・CI・ステージングで行うこと。
#
# 動作:
#   検体を解析対象スコープ内へ一時設置し、ゲートがそれを検出するかを見る。
#   **判定は3値**（VERIFIED / DEGRADED / BLIND）であり、2値にしない。
#   「0 件」は、そのゲートが VERIFIED でない限り合格として扱ってはならない。
#
#   --gate=phpstan の固有価値は「`excludePaths` がスコープを黙って潰していないか」を
#   検出できる**唯一の手段**である点にある。件数を見るだけでは
#   「9割除外されているが1割は解析されている」状態を拾えない。
#
# 終了コード:
#   0 : VERIFIED（期待した全項目を期待した重大度で検出。以後この 0 件は PASS と表記してよい）
#   1 : DEGRADED / BLIND（**このゲートを合格基準に使ってはならない**）
#   2 : 設定ミス・実行不能・検体の撤去に失敗

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=lib/find-bin.sh disable=SC1091
. "${SCRIPT_DIR}/lib/find-bin.sh"

GATE=""
PLANT_DIR=""
CONFIG=""
LEVEL=""
TESTVERSION=""
LOGGER=""
LOGFILE=""
PHP_BIN=""
KEEP=0
MEMORY_LIMIT="1G"

while [ "$#" -gt 0 ]; do
  arg="$1"
  shift
  case "${arg}" in
    --gate=*)        GATE="${arg#--gate=}" ;;
    --plant-dir=*)   PLANT_DIR="${arg#--plant-dir=}" ;;
    --config=*)      CONFIG="${arg#--config=}" ;;
    --level=*)       LEVEL="${arg#--level=}" ;;
    --testversion=*) TESTVERSION="${arg#--testversion=}" ;;
    --logger=*)      LOGGER="${arg#--logger=}" ;;
    --log=*)         LOGFILE="${arg#--log=}" ;;
    --php-bin=*)     PHP_BIN="${arg#--php-bin=}" ;;
    --keep)          KEEP=1 ;;
    --memory-limit=*) MEMORY_LIMIT="${arg#--memory-limit=}" ;;
    -h|--help)
      sed -n '2,30p' "$0" >&2
      exit 2
      ;;
    *)
      printf 'Error: 不明な引数です: %s\n' "${arg}" >&2
      exit 2
      ;;
  esac
done

# --gate 省略時に推測しない。
if [ -z "${GATE}" ]; then
  cat >&2 <<'EOF'
Error: --gate=phpstan|phpcompat|logger を指定してください。
  既定値は設けていません。どのゲートを検証しているかが曖昧なまま
  「検証済み」と記録されると、検証の意味が失われます。
EOF
  exit 2
fi

case "${GATE}" in
  phpstan|phpcompat|logger) ;;
  *)
    printf 'Error: --gate は phpstan / phpcompat / logger のいずれかです: %s\n' "${GATE}" >&2
    exit 2
    ;;
esac

JQ_BIN="$(find_bin_require jq path)" || exit 2

TMPD="$(mktemp -d)"
if [ -z "${TMPD}" ] || [ ! -d "${TMPD}" ]; then
  printf 'Error: 一時ディレクトリを作成できませんでした\n' >&2
  exit 2
fi

# 設置した検体は必ず撤去する。撤去できなかった場合は最後に exit 2 で知らせる。
PLANTED_LIST="${TMPD}/planted.txt"
: > "${PLANTED_LIST}"

cleanup_planted() {
  if [ "${KEEP}" -eq 1 ]; then
    return 0
  fi
  if [ -s "${PLANTED_LIST}" ]; then
    while IFS= read -r p; do
      [ -n "${p}" ] || continue
      rm -f "${p}" 2>/dev/null || true
    done < "${PLANTED_LIST}"
  fi
}
trap 'cleanup_planted; rm -rf "${TMPD}"' EXIT INT TERM

# 検体のファイル名。pid と epoch を含め、既存ファイルと衝突させない。
PROBE_STAMP="$$_$(date +%s)"

plant_file() {
  # $1: 設置先の絶対パス / stdin: 中身
  local dest="$1"
  if [ -e "${dest}" ]; then
    printf 'Error: 設置先が既に存在します（上書きしません）: %s\n' "${dest}" >&2
    exit 2
  fi
  cat > "${dest}"
  printf '%s\n' "${dest}" >> "${PLANTED_LIST}"
}

require_plant_dir() {
  if [ -z "${PLANT_DIR}" ]; then
    cat >&2 <<'EOF'
Error: --plant-dir=<解析対象スコープ内のディレクトリ> を指定してください。
  既定値は設けていません。**解析対象スコープの内側**でなければ、
  「ゲートがスコープを黙って潰していないか」を確かめるという検証の目的を果たせません。
EOF
    exit 2
  fi
  if [ ! -d "${PLANT_DIR}" ]; then
    printf 'Error: --plant-dir がディレクトリではありません: %s\n' "${PLANT_DIR}" >&2
    exit 2
  fi
  if [ ! -w "${PLANT_DIR}" ]; then
    printf 'Error: --plant-dir へ書き込めません: %s\n' "${PLANT_DIR}" >&2
    exit 2
  fi
}

# 3値判定の結果とその後の案内を出す共通処理。
# ★ 3-3 が最重要。「外す」だけで終わると、守備範囲に穴が開いたまま「全ゲート緑」になる。
# shellcheck disable=SC2016
report_verdict() {
  # $1: ゲート名 / $2: バージョン / $3: 判定 / $4: 検出数 / $5: 期待数 / $6: 穴埋め案内（改行区切り）
  local gate="$1" version="$2" verdict="$3" found="$4" expected="$5" fill="$6"
  printf '\n'
  printf '| ゲート | バージョン | 自己検証 | 結果の表記 |\n'
  printf '|---|---|---|---|\n'
  case "${verdict}" in
    VERIFIED)
      printf '| %s | %s | VERIFIED (%s/%s) | 以後この 0 件は `PASS` と表記してよい |\n' \
        "${gate}" "${version}" "${found}" "${expected}"
      ;;
    DEGRADED)
      printf '| %s | %s | DEGRADED (%s/%s) | 0 件は `SKIPPED (degraded)`。**合格ではない** |\n' \
        "${gate}" "${version}" "${found}" "${expected}"
      ;;
    BLIND)
      printf '| %s | %s | BLIND (0/%s) | 0 件は `NOT-RUN`。**合格ではない** |\n' \
        "${gate}" "${version}" "${expected}"
      ;;
  esac
  if [ "${verdict}" != "VERIFIED" ]; then
    printf '\n'
    printf '**このゲートを Fatal ゲート（単独の受入基準）から外すこと。**\n'
    printf '外すだけで終えてはならない。守備範囲に穴が開いたまま「全ゲート緑」になる。\n'
    printf '\n穴埋めの担当ゲート:\n%s\n' "${fill}"
    printf '\n穴埋め先のゲートが**まだ自己検証されていない場合は BLOCK**（作業を止めて報告する）。\n'
  fi
}

case "${GATE}" in

  # ------------------------------------------------------------------
  phpstan)
    require_plant_dir
    PHPSTAN_BIN="$(find_bin_require phpstan)" || exit 2
    [ -n "${CONFIG}" ] || CONFIG="phpstan.neon"
    if [ ! -f "${CONFIG}" ]; then
      printf 'Error: PHPStan 設定ファイルがありません: %s\n' "${CONFIG}" >&2
      exit 2
    fi

    # 検体の中身。すべて未呼び出し関数の中に置く（万一 include されても副作用が無い）。
    # 型はこの検体自身の宣言から作る。プロジェクトの stub に依存させない。
    PROBE_SRC="${TMPD}/probe.php"
    cat > "${PROBE_SRC}" <<'PROBE'
<?php
/** ゲート自己検証用の一時ファイル。検証終了時に自動削除される。 */
class GateProbeDeclared { public int $declared = 0; }
/** @return array|false */
function gate_probe_array_or_false() { return false; }
function gate_probe_never_called(): void
{
    $v = gate_probe_array_or_false();
    $sink = $v['key'];
    foreach ($v as $x) { $sink = $x; }
    $o = new GateProbeDeclared();
    $sink = $o->undeclaredProperty;
    $sink = $undefinedVariable;
    $sink = (string) [1, 2];
    unset($sink);
}
PROBE

    # まず**スコープ外**（検体をパス引数で直接指定）で解析し、期待集合を自己校正する。
    # 期待値を数値でハードコードしないため、PHPStan のバージョンが動いても壊れない。
    #
    # ★ 基準線も**プロジェクトの実運用設定**（同じ level・同じ stub）で取る。
    #   別の level で基準線を取ると、level 差がそのまま「検出できなかった」に化けて
    #   偽の DEGRADED になる。ここで変えてよいのは**検体の置き場所だけ**である。
    LEVEL_ARG=""
    [ -z "${LEVEL}" ] || LEVEL_ARG="--level=${LEVEL}"

    ec=0
    # shellcheck disable=SC2086
    "${PHPSTAN_BIN}" analyse --configuration="${CONFIG}" ${LEVEL_ARG} \
      --error-format=json --no-progress --memory-limit="${MEMORY_LIMIT}" \
      "${PROBE_SRC}" > "${TMPD}/base.json" 2> "${TMPD}/base.err" || ec=$?
    if [ ! -s "${TMPD}/base.json" ] || ! "${JQ_BIN}" -e . "${TMPD}/base.json" >/dev/null 2>&1; then
      printf 'Error: 検体単独の解析に失敗しました（exit code: %s）。検証不能です。\n' "${ec}" >&2
      cat "${TMPD}/base.err" >&2
      exit 2
    fi
    "${JQ_BIN}" -r '[.files // {} | .[].messages[] | .identifier // "<none>"] | unique[]' \
      "${TMPD}/base.json" > "${TMPD}/expected.txt"

    expected_n=$(wc -l < "${TMPD}/expected.txt" | tr -d ' ')
    if [ "${expected_n}" -eq 0 ]; then
      {
        printf 'Error: 検体単独でも1件も検出できませんでした。\n'
        printf '  ゲートの検証以前に、PHPStan 自体が期待どおり動いていません。**BLOCK。**\n'
      } >&2
      exit 2
    fi

    # 次に**解析対象スコープ内**へ設置し、プロジェクトの実運用設定で解析する。
    PLANTED="${PLANT_DIR}/__gate_probe_${PROBE_STAMP}.php"
    plant_file "${PLANTED}" < "${PROBE_SRC}"

    ec=0
    # shellcheck disable=SC2086
    "${PHPSTAN_BIN}" analyse --configuration="${CONFIG}" ${LEVEL_ARG} \
      --error-format=json --no-progress --memory-limit="${MEMORY_LIMIT}" \
      > "${TMPD}/scope.json" 2> "${TMPD}/scope.err" || ec=$?
    if [ ! -s "${TMPD}/scope.json" ] || ! "${JQ_BIN}" -e . "${TMPD}/scope.json" >/dev/null 2>&1; then
      printf 'Error: スコープ内解析が JSON を返しませんでした（exit code: %s）。検証不能です。\n' "${ec}" >&2
      cat "${TMPD}/scope.err" >&2
      exit 2
    fi

    # shellcheck disable=SC2016
    "${JQ_BIN}" -r --arg planted "${PLANTED}" '
      [ .files // {} | to_entries[] | select(.key | endswith($planted | split("/") | last))
        | .value.messages[] | .identifier // "<none>" ] | unique[]
    ' "${TMPD}/scope.json" > "${TMPD}/observed.txt"

    found_n=$(comm -12 <(sort "${TMPD}/expected.txt") <(sort "${TMPD}/observed.txt") | wc -l | tr -d ' ')

    printf 'PHPStan ゲート自己検証\n'
    printf '  設定           : %s\n' "${CONFIG}"
    printf '  設置先         : %s\n' "${PLANTED}"
    printf '  期待（検体単独）: %s 件\n' "${expected_n}"
    printf '  観測（スコープ内）: %s 件\n' "${found_n}"
    if [ "${found_n}" -lt "${expected_n}" ]; then
      printf '  検出できなかった identifier:\n'
      comm -23 <(sort "${TMPD}/expected.txt") <(sort "${TMPD}/observed.txt") | sed 's/^/    - /'
    fi

    PHPSTAN_VER="$("${PHPSTAN_BIN}" --version 2>/dev/null | head -1 || true)"
    # shellcheck disable=SC2016
    FILL_PHPSTAN='  — スコープが潰されている場合 → phpstan.neon の `excludePaths` / `paths` を実測で見直す
  — level が低い場合           → `scripts/probe-phpstan-levels.sh` で下限 level を実測する
  — stub 不足の場合            → 対象 API の stub を `scanFiles` へ追加する'

    if [ "${found_n}" -eq 0 ]; then
      report_verdict "PHPStan" "${PHPSTAN_VER}" BLIND 0 "${expected_n}" "${FILL_PHPSTAN}"
      printf '\n★ 検体をスコープ内へ設置したのに1件も検出されていません。\n'
      # shellcheck disable=SC2016
      printf '  `excludePaths` が設置先を除外しているか、`paths` が設置先を含んでいません。\n'
      printf '  **件数だけを見ていては絶対に気づけない状態です。**\n'
      verdict_code=1
    elif [ "${found_n}" -lt "${expected_n}" ]; then
      report_verdict "PHPStan" "${PHPSTAN_VER}" DEGRADED "${found_n}" "${expected_n}" "${FILL_PHPSTAN}"
      verdict_code=1
    else
      report_verdict "PHPStan" "${PHPSTAN_VER}" VERIFIED "${found_n}" "${expected_n}" ""
      verdict_code=0
    fi
    ;;

  # ------------------------------------------------------------------
  phpcompat)
    require_plant_dir
    PHPCS_BIN="$(find_bin_require phpcs)" || exit 2
    if [ -z "${TESTVERSION}" ]; then
      printf 'Error: --testversion=<x.y> または <x.y-x.y> を指定してください。\n' >&2
      exit 2
    fi
    _ver_re='[0-9]+\.[0-9]+'
    if ! printf '%s' "${TESTVERSION}" | grep -qE "^(${_ver_re}|${_ver_re}-|-${_ver_re}|${_ver_re}-${_ver_re})$"; then
      printf 'Error: --testversion の書式が不正です: %s\n' "${TESTVERSION}" >&2
      exit 2
    fi

    PROBE_DIR="${SCRIPT_DIR}/probes/phpcompat"
    if [ ! -d "${PROBE_DIR}" ]; then
      printf 'Error: 検体ディレクトリがありません: %s\n' "${PROBE_DIR}" >&2
      exit 2
    fi

    # 期待項目を検体から読む
    EXPECT="${TMPD}/expect.tsv"
    : > "${EXPECT}"
    for f in "${PROBE_DIR}"/*.php; do
      [ -f "${f}" ] || continue
      grep -E '^[[:space:]]*// @gate-expect[[:space:]]' "${f}" 2>/dev/null | while IFS= read -r line; do
        sev="$(printf '%s' "${line}" | sed -n 's/.*@gate-expect[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p')"
        tok="$(printf '%s' "${line}" | sed -n 's/.*@gate-expect[[:space:]]\{1,\}[^[:space:]]\{1,\}[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p')"
        [ -n "${tok}" ] || continue
        printf '%s\t%s\n' "${sev}" "${tok}" >> "${EXPECT}"
      done
      base="$(basename "${f}")"
      plant_file "${PLANT_DIR}/__gate_probe_${PROBE_STAMP}_${base}" < "${f}"
    done

    expected_n=$(wc -l < "${EXPECT}" | tr -d ' ')
    if [ "${expected_n}" -eq 0 ]; then
      printf 'Error: 検体に @gate-expect マーカーがありません: %s\n' "${PROBE_DIR}" >&2
      exit 2
    fi

    ec=0
    if [ -n "${CONFIG}" ]; then
      "${PHPCS_BIN}" --standard="${CONFIG}" --runtime-set testVersion "${TESTVERSION}" \
        --extensions=php --report=json "${PLANT_DIR}" > "${TMPD}/cs.json" 2> "${TMPD}/cs.err" || ec=$?
    else
      "${PHPCS_BIN}" --standard=PHPCompatibility --runtime-set testVersion "${TESTVERSION}" \
        --extensions=php --report=json "${PLANT_DIR}" > "${TMPD}/cs.json" 2> "${TMPD}/cs.err" || ec=$?
    fi
    if [ ! -s "${TMPD}/cs.json" ] || ! "${JQ_BIN}" -e . "${TMPD}/cs.json" >/dev/null 2>&1; then
      printf 'Error: phpcs が JSON を返しませんでした（exit code: %s）。検証不能です。\n' "${ec}" >&2
      cat "${TMPD}/cs.err" >&2
      exit 2
    fi

    # shellcheck disable=SC2016
    "${JQ_BIN}" -r --arg stamp "${PROBE_STAMP}" '
      .files // {} | to_entries[] | select(.key | contains($stamp))
      | .value.messages[] | "\(.type)\t\(.source)\t\(.message)"
    ' "${TMPD}/cs.json" > "${TMPD}/cs.tsv"

    RESULT="${TMPD}/result.tsv"
    : > "${RESULT}"
    while IFS=$'\t' read -r sev tok; do
      [ -n "${tok}" ] || continue
      hit="$(grep -F -- "${tok}" "${TMPD}/cs.tsv" | head -1 || true)"
      if [ -z "${hit}" ]; then
        printf '%s\t%s\t未検出\n' "${sev}" "${tok}" >> "${RESULT}"
      else
        actual="$(printf '%s' "${hit}" | cut -f1)"
        printf '%s\t%s\t%s\n' "${sev}" "${tok}" "${actual}" >> "${RESULT}"
      fi
    done < "${EXPECT}"

    exact_n=$(awk -F'\t' '$1 == $3' "${RESULT}" | wc -l | tr -d ' ')
    any_n=$(awk -F'\t' '$3 != "未検出"' "${RESULT}" | wc -l | tr -d ' ')

    printf 'PHPCompatibility ゲート自己検証\n'
    printf '  testVersion : %s\n' "${TESTVERSION}"
    printf '  設置先      : %s\n\n' "${PLANT_DIR}"
    printf '  %-28s %-10s %s\n' "照合トークン" "期待" "実際"
    awk -F'\t' '{ printf "  %-28s %-10s %s\n", $2, $1, $3 }' "${RESULT}"

    # ★ 判定対象は phpcs 本体ではなく **PHPCompatibility スニフのバージョン**である。
    #   phpcs のバージョンを代わりに出すと、読み手が守備範囲を取り違える。
    #   特定できない場合は**それ自体を出す**（別の値で埋めない）。
    phpcompat_ver=""
    for _il in ./vendor/composer/installed.json \
               $(find . -maxdepth 5 -path '*/vendor/composer/installed.json' 2>/dev/null | head -3); do
      [ -f "${_il}" ] || continue
      phpcompat_ver="$("${JQ_BIN}" -r '
        (.packages // .) | map(select(.name == "phpcompatibility/php-compatibility"))
        | .[0].version // empty' "${_il}" 2>/dev/null || true)"
      [ -n "${phpcompat_ver}" ] && break
    done
    _phpcs_only="$("${PHPCS_BIN}" --version 2>/dev/null | sed -n 's/.*version \([0-9.]\{1,\}\).*/\1/p' || true)"
    if [ -n "${phpcompat_ver}" ]; then
      PHPCS_VER="PHPCompatibility ${phpcompat_ver} / phpcs ${_phpcs_only:-不明}"
    else
      PHPCS_VER="PHPCompatibility **バージョン特定不能** / phpcs ${_phpcs_only:-不明}"
    fi
    # shellcheck disable=SC2016
    FILL_PHPCOMPAT='  — 削除 API   → PHPStan の `function.notFound` ／ 対象バージョン実機での `php -l`
  — 非推奨 API → 実行時ログ（E_DEPRECATED）。`scripts/php-migration-logger.php`
  — 構文変更   → **対象バージョンのバイナリでの `php -l`**（`scripts/lint-target-version.sh` では代替できない）'

    if [ "${any_n}" -eq 0 ]; then
      report_verdict "PHPCompatibility" "${PHPCS_VER}" BLIND 0 "${expected_n}" "${FILL_PHPCOMPAT}"
      verdict_code=1
    elif [ "${exact_n}" -lt "${expected_n}" ]; then
      report_verdict "PHPCompatibility" "${PHPCS_VER}" DEGRADED "${exact_n}" "${expected_n}" "${FILL_PHPCOMPAT}"
      printf '\n★「ERROR 0 件」を単独の受入基準にしてはならない。\n'
      printf '  期待を ERROR としたものが WARNING でしか出ない場合、\n'
      # shellcheck disable=SC2016
      printf '  `ignore_warnings_on_exit` 運用では**終了コードが常に 0 になる**。\n'
      verdict_code=1
    else
      report_verdict "PHPCompatibility" "${PHPCS_VER}" VERIFIED "${exact_n}" "${expected_n}" ""
      verdict_code=0
    fi
    ;;

  # ------------------------------------------------------------------
  logger)
    if [ -z "${LOGGER}" ] || [ -z "${LOGFILE}" ]; then
      printf 'Error: --logger=<path> と --log=<path> を指定してください。\n' >&2
      exit 2
    fi
    if [ ! -f "${LOGGER}" ]; then
      printf 'Error: ロガーがありません: %s\n' "${LOGGER}" >&2
      exit 2
    fi
    if [ -z "${PHP_BIN}" ]; then
      PHP_BIN="$(find_bin_require php path)" || exit 2
    fi
    if [ ! -x "${PHP_BIN}" ] && ! command -v "${PHP_BIN}" >/dev/null 2>&1; then
      printf 'Error: PHP を実行できません: %s\n' "${PHP_BIN}" >&2
      exit 2
    fi

    DRIVER="${TMPD}/driver.php"
    cat > "${DRIVER}" <<PHPDRIVER
<?php
// ロガー自己検証ドライバ。E_WARNING / E_DEPRECATED / @ 抑制 / Fatal を意図的に起こす。
define('PHP_MIGRATION_LOG', '${LOGFILE}');
define('PHP_MIGRATION_ROOT', '${TMPD}');
define('PHP_MIGRATION_OWN_PATHS', '${TMPD}');
define('PHP_MIGRATION_EXPIRE', '2999-12-31');
// WP_DEBUG=false 相当のマスク。ロガーはマスクに関係なく拾えなければならない。
error_reporting(E_ALL & ~E_DEPRECATED & ~E_NOTICE & ~E_WARNING);
require '${LOGGER}';

\$b = false;
\$sink = \$b['warning_case'];          // E_WARNING
\$sink = @\$b['suppressed_case'];      // E_WARNING（@ 抑制）
\$sink = strlen(null);                 // E_DEPRECATED（8.1+）
require '${TMPD}/nonexistent_fatal.php'; // Fatal
PHPDRIVER

    rm -f "${LOGFILE}" 2>/dev/null || true
    "${PHP_BIN}" "${DRIVER}" >/dev/null 2>&1 || true

    if [ ! -f "${LOGFILE}" ]; then
      {
        printf 'Error: ログファイルが作成されませんでした: %s\n' "${LOGFILE}"
        printf '  **ロガーが起動していません。検証不能です。**\n'
        printf '  「ログが空＝警告 0 件＝安全」と解釈しないでください。\n'
      } >&2
      exit 2
    fi

    expected_n=4
    found_n=0
    printf 'ロガー自己検証\n'
    printf '  ロガー : %s\n' "${LOGGER}"
    printf '  ログ   : %s\n\n' "${LOGFILE}"

    check_log() {
      # $1: 説明 / $2: grep パターン
      if grep -q -- "$2" "${LOGFILE}" 2>/dev/null; then
        printf '  [OK] %s\n' "$1"
        found_n=$((found_n + 1))
      else
        printf '  [NG] %s\n' "$1"
      fi
    }
    check_log "起動記録（BOOT 行）がある" 'lv:BOOT'
    check_log "マスクされた E_WARNING を捕捉している" 'lv:E_WARNING'
    check_log "@ 抑制を sup:1 として区別している" 'sup:1'
    check_log "Fatal を捕捉している" 'lv:E_ERROR'

    FILL_LOGGER='  — ロガーが起動していない → 設置位置（auto_prepend_file / mu-plugin）を見直す
  — 一部しか拾えない       → set_error_handler の引数がちょうど 4 個か、
                              error_reporting のマスクで早期 return していないかを確認する'

    if [ "${found_n}" -eq 0 ]; then
      report_verdict "実行時ロガー" "-" BLIND 0 "${expected_n}" "${FILL_LOGGER}"
      verdict_code=1
    elif [ "${found_n}" -lt "${expected_n}" ]; then
      report_verdict "実行時ロガー" "-" DEGRADED "${found_n}" "${expected_n}" "${FILL_LOGGER}"
      verdict_code=1
    else
      report_verdict "実行時ロガー" "-" VERIFIED "${found_n}" "${expected_n}" ""
      verdict_code=0
    fi
    ;;
esac

# ---- 撤去の確認（残置は事故） ----

cleanup_planted
leftover=0
if [ "${KEEP}" -eq 0 ] && [ -s "${PLANTED_LIST}" ]; then
  while IFS= read -r p; do
    [ -n "${p}" ] || continue
    if [ -e "${p}" ]; then
      printf 'Error: 検体を撤去できませんでした: %s\n' "${p}" >&2
      leftover=$((leftover + 1))
    fi
  done < "${PLANTED_LIST}"
fi
if [ "${leftover}" -gt 0 ]; then
  printf '  **残置は事故です。手動で削除してください。**\n' >&2
  exit 2
fi
if [ "${KEEP}" -eq 1 ] && [ -s "${PLANTED_LIST}" ]; then
  printf '\n警告: --keep により検体を残しました。**必ず手動で削除してください。**\n' >&2
  sed 's/^/  /' "${PLANTED_LIST}" >&2
fi

exit "${verdict_code}"
