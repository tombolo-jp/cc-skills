#!/usr/bin/env bash
# 実行時ログと静的解析結果を突合する
#
# 使い方:
#   scripts/correlate-static-runtime.sh --log=site.log --static=phpstan.json --rev=$(git rev-parse HEAD)
#
# 前提:
#   - `--static` は `phpstan analyse --error-format=json` の出力ファイル。
#   - `--log` は `scripts/php-migration-logger.php` が出力した LTSV。
#   - **ログ収集時と静的解析実行時のリビジョンが同一であること。**
#
# 動作:
#   主キーは **`file:line`** である。
#     - `message` は使えない（実行時「Trying to access array offset on value of type bool」と
#       PHPStan「Cannot access offset 'x' on array|false.」は同じ欠陥でも文字列として無関係）。
#     - `identifier` はキーに使えない（実行時側には errno しか無く、E_WARNING ↔ 複数 identifier は
#       N:M で逆写像できない）。分類にのみ使う。
#
#   結果を3区分で出す。
#     [A] 実行時に出て、静的解析も検出した   … ゲートは機能している
#     [B] 実行時に出たが、静的解析は沈黙     … ★要調査（ゲート設定の見直し）
#     [C] 静的解析は検出したが実行時に出ず   … 偽陽性候補 / 未到達経路（仕分けの入力）
#
#   ★ **区分 B が 0 件でも「0 件だった」と出力する。**
#     何も出さないと、実施したのか未実施なのかが区別できない。
#
# 終了コード:
#   0 : 区分 B が 0 件
#   1 : 区分 B が 1 件以上（**ゲート設定の見直しが必要**）
#   2 : 判定不能（入力不正 / リビジョン不一致 / ログに BOOT 記録が無い）

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=lib/find-bin.sh disable=SC1091
. "${SCRIPT_DIR}/lib/find-bin.sh"

LOGS=""
STATIC=""
REV=""
ROOT=""
MATCH="line"
FORMAT="table"

while [ "$#" -gt 0 ]; do
  arg="$1"
  shift
  case "${arg}" in
    --log=*)    LOGS="${arg#--log=}" ;;
    --static=*) STATIC="${arg#--static=}" ;;
    --rev=*)    REV="${arg#--rev=}" ;;
    --root=*)   ROOT="${arg#--root=}" ;;
    --match=*)  MATCH="${arg#--match=}" ;;
    --format=*) FORMAT="${arg#--format=}" ;;
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

if [ -z "${LOGS}" ] || [ -z "${STATIC}" ]; then
  printf 'Error: --log=<file> と --static=<phpstan json> を指定してください。\n' >&2
  exit 2
fi

# --rev は必須。file:line はコードが変わると壊れるため、
# リビジョンを照合しないまま突合すると**結果が無意味になる**。黙って進めない。
if [ -z "${REV}" ]; then
  cat >&2 <<'EOF'
Error: --rev=<sha> を指定してください（例: --rev=$(git rev-parse HEAD)）。
  突合の主キーは file:line です。ログ収集時と静的解析実行時のリビジョンが違うと、
  行がずれて突合結果が無意味になります。省略を許すとその検証が飛ぶため必須にしています。
EOF
  exit 2
fi
if ! printf '%s' "${REV}" | grep -qE '^[0-9a-f]{7,40}$'; then
  printf 'Error: --rev の書式が不正です: %s\n' "${REV}" >&2
  exit 2
fi

case "${MATCH}" in
  line|file) ;;
  *)
    printf 'Error: --match は line / file のいずれかです: %s\n' "${MATCH}" >&2
    exit 2
    ;;
esac

case "${FORMAT}" in
  table|tsv|md) ;;
  *)
    printf 'Error: --format は table / tsv / md のいずれかです: %s\n' "${FORMAT}" >&2
    exit 2
    ;;
esac

JQ_BIN="$(find_bin_require jq path)" || exit 2

if [ -z "${ROOT}" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "${ROOT}" ] || ROOT="$(pwd)"
fi
ROOT="$(cd -- "${ROOT}" && pwd)"

# リビジョン照合
current_rev="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || true)"
if [ -z "${current_rev}" ]; then
  printf 'Error: git リビジョンを取得できません: %s\n' "${ROOT}" >&2
  exit 2
fi
rev_len=${#REV}
if [ "${REV}" != "$(printf '%s' "${current_rev}" | cut -c1-"${rev_len}")" ]; then
  {
    printf 'Error: リビジョンが一致しません。\n'
    printf '  指定 --rev : %s\n' "${REV}"
    printf '  現在 HEAD  : %s\n' "${current_rev}"
    printf '  **ログ収集時と静的解析実行時のリビジョンが違います。突合結果は無意味です。**\n'
  } >&2
  exit 2
fi

if [ ! -f "${STATIC}" ]; then
  printf 'Error: 静的解析の JSON がありません: %s\n' "${STATIC}" >&2
  exit 2
fi
if ! "${JQ_BIN}" -e . "${STATIC}" >/dev/null 2>&1; then
  printf 'Error: 静的解析の JSON を読めません: %s\n' "${STATIC}" >&2
  printf '  PHPStan は解析不能でも exit 1 / 出力空を返します。**判定不能です。**\n' >&2
  exit 2
fi

TMPD="$(mktemp -d)"
if [ -z "${TMPD}" ] || [ ! -d "${TMPD}" ]; then
  printf 'Error: 一時ディレクトリを作成できませんでした\n' >&2
  exit 2
fi
trap 'rm -rf "${TMPD}"' EXIT INT TERM

# ---- 実行時側 ----
ALL="${TMPD}/all.ltsv"
: > "${ALL}"
_old_ifs="${IFS}"
IFS=','
for f in ${LOGS}; do
  IFS="${_old_ifs}"
  [ -n "${f}" ] || continue
  if [ ! -f "${f}" ]; then
    printf 'Error: ログファイルがありません: %s\n' "${f}" >&2
    exit 2
  fi
  cat "${f}" >> "${ALL}"
  IFS=','
done
IFS="${_old_ifs}"

boot_count=$(grep -c 'lv:BOOT' "${ALL}" 2>/dev/null || true)
[ -n "${boot_count}" ] || boot_count=0

RUNTIME="${TMPD}/runtime.tsv"
awk -v match_mode="${MATCH}" '
  BEGIN { FS = "\t" }
  {
    delete v
    for (i = 1; i <= NF; i++) {
      p = index($i, ":")
      if (p > 0) { v[substr($i, 1, p - 1)] = substr($i, p + 1) }
    }
    lv = ("lv" in v) ? v["lv"] : ""
    if (lv == "" || lv == "BOOT" || lv == "HINT" || lv == "DEDUP") { next }
    at = ("at" in v) ? v["at"] : ""
    if (at == "") { next }
    key = at
    if (match_mode == "file") { sub(/:[0-9]+$/, "", key) }
    print key "\t" lv
  }
' "${ALL}" | sort -u > "${RUNTIME}"

# ---- 静的解析側 ----
STATIC_TSV="${TMPD}/static.tsv"
# shellcheck disable=SC2016
"${JQ_BIN}" -r --arg root "${ROOT}/" --arg match "${MATCH}" '
  .files // {} | to_entries[] | .key as $f | .value.messages[]
  | ((if ($f | startswith($root)) then ($f | ltrimstr($root)) else $f end)) as $rel
  | (if $match == "file" then $rel else ($rel + ":" + (.line | tostring)) end) as $key
  | [$key, (.identifier // "<none>")] | @tsv
' "${STATIC}" | sort -u > "${STATIC_TSV}"

RUNTIME_KEYS="${TMPD}/runtime.keys"
STATIC_KEYS="${TMPD}/static.keys"
cut -f1 "${RUNTIME}" | sort -u > "${RUNTIME_KEYS}"
cut -f1 "${STATIC_TSV}" | sort -u > "${STATIC_KEYS}"

A_KEYS="${TMPD}/a.keys"; comm -12 "${RUNTIME_KEYS}" "${STATIC_KEYS}" > "${A_KEYS}"
B_KEYS="${TMPD}/b.keys"; comm -23 "${RUNTIME_KEYS}" "${STATIC_KEYS}" > "${B_KEYS}"
C_KEYS="${TMPD}/c.keys"; comm -13 "${RUNTIME_KEYS}" "${STATIC_KEYS}" > "${C_KEYS}"

a_n=$(wc -l < "${A_KEYS}" | tr -d ' ')
b_n=$(wc -l < "${B_KEYS}" | tr -d ' ')
c_n=$(wc -l < "${C_KEYS}" | tr -d ' ')

if [ "${boot_count}" -eq 0 ] && [ "$(wc -l < "${RUNTIME_KEYS}" | tr -d ' ')" -eq 0 ]; then
  {
    printf 'Error: 実行時ログに BOOT 記録もエラー行もありません。\n'
    printf '  **ロガーが起動していない可能性があります。突合は判定不能です。**\n'
    printf '  「実行時に何も出なかった＝静的解析の指摘は全部偽陽性」と読まないでください。\n'
  } >&2
  exit 2
fi

# ---- パス正規化の不一致検出（実務で必ず一度は踏む） ----
if [ "${a_n}" -eq 0 ] && [ "${c_n}" -eq 0 ] && [ "${b_n}" -gt 0 ]; then
  {
    printf '[!] 区分 A が 0 件、C も 0 件で B だけが %s 件です。パス正規化の不一致が疑われます。\n' "${b_n}"
    printf '    実行時ログ側の先頭パス: %s\n' "$(head -1 "${RUNTIME_KEYS}")"
    printf '    静的解析側の先頭パス  : %s\n' "$(head -1 "${STATIC_KEYS}" 2>/dev/null || echo '(なし)')"
    printf '    → PHP_MIGRATION_ROOT と --root が同じディレクトリを指しているか確認してください。\n'
  } >&2
fi

# ---- 出力 ----

emit_section() {
  # $1: ラベル / $2: キーファイル / $3: 補足TSV（キー→種別）
  local label="$1" keyfile="$2" detail="$3"
  printf '%s\n' "${label}"
  if [ ! -s "${keyfile}" ]; then
    printf '  （0 件）\n'
    return 0
  fi
  while IFS= read -r k; do
    [ -n "${k}" ] || continue
    kinds="$(awk -F'\t' -v key="${k}" '$1 == key { printf "%s ", $2 }' "${detail}")"
    printf '  %-60s %s\n' "${k}" "${kinds}"
  done < "${keyfile}"
}

case "${FORMAT}" in
  tsv)
    while IFS= read -r k; do [ -n "${k}" ] && printf 'A\t%s\n' "${k}"; done < "${A_KEYS}"
    while IFS= read -r k; do [ -n "${k}" ] && printf 'B\t%s\n' "${k}"; done < "${B_KEYS}"
    while IFS= read -r k; do [ -n "${k}" ] && printf 'C\t%s\n' "${k}"; done < "${C_KEYS}"
    ;;
  md|table)
    printf '実行時ログ × 静的解析 の突合（rev=%s / --match=%s）\n\n' "${REV}" "${MATCH}"
    printf '[A] 実行時に出て、静的解析も検出した ............ %s 件   （ゲートは機能している）\n' "${a_n}"
    printf '[B] 実行時に出たが、静的解析は沈黙 ............... %s 件   ★要調査\n' "${b_n}"
    printf '[C] 静的解析は検出したが、実行時には出なかった ... %s 件   （偽陽性候補 / 未到達経路）\n\n' "${c_n}"

    emit_section "[B] 実行時に出たが静的解析が沈黙した箇所:" "${B_KEYS}" "${RUNTIME}"
    printf '\n'
    printf '  区分 B は**ツールの限界と結論づける前に、必ず次の5点を確認する**:\n'
    printf '    1. そのカテゴリの下限 level を満たしているか（scripts/probe-phpstan-levels.sh で実測する）\n'
    printf '    2. level と独立した感度パラメータが有効か（reportPossiblyNonexistent*ArrayOffset。\n'
    printf '       references/detection-gates.md §2「必須パラメータ」。Undefined array key ならまずここ）\n'
    printf '    3. そのゲートの守備範囲か（references/detection-gates.md §1）\n'
    printf '    4. 必要な stub / bootstrapFiles が入っているか（入っていないと型が mixed に落ちる）\n'
    printf '    5. ignoreErrors / baseline に入っていないか\n'
    printf '  → 5点すべてを否定できて初めて「ツールの原理的限界」と記録してよい。\n\n'

    emit_section "[C] 静的解析のみ（仕分けの入力。実行時に出ないことは安全の証明ではない）:" "${C_KEYS}" "${STATIC_TSV}"
    printf '\n'
    printf '  区分 C を「実行時に出ないから偽陽性」と即断しない。**未到達経路の可能性**がある。\n'
    printf '  判定根拠は「到達不能であることを示す」か「実測で示す」のいずれかで書くこと。\n'
    ;;
esac

if [ "${b_n}" -gt 0 ]; then
  exit 1
fi
exit 0
