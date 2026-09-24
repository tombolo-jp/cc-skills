#!/usr/bin/env bash
# PHPStan の identifier ごとの「下限 level」を実測する
#
# 使い方:
#   probe-phpstan-levels.sh --php-version=8.3
#   probe-phpstan-levels.sh --php-version=8.3 --format=md > /tmp/table.md
#   probe-phpstan-levels.sh --php-version=8.3 --levels=0-10 --probe-dir=./scripts/probes/phpstan
#
# 前提: PHPStan が導入済みであること（`./vendor/bin/phpstan` または PATH 上）。
#   jq は不要（このスクリプトは phpstan の JSON を jq で読むため実際には必要。下記参照）。
#   検体（`probes/phpstan/*.php`）は**このスキルに同梱されたもの**を使い、
#   プロジェクトの neon / stub / vendor に一切依存しない（design §7.3）。
#
# 動作:
#   検体中の `// @probe-expect <identifier> <variant>` を「**直後の1行**に対する期待」として読み、
#   level を昇順に総当たりして、その identifier が最初に報告される level を記録する。
#   出力は `identifier × 型の分かり具合` の**2次元表**である。
#
#   ★ 1次元表（identifier → 下限 level）は成立しない。同一 identifier でも下限は
#     型の分かり具合で2〜3段動く（design §0 M2）。1次元にすると下限を過小報告し、
#     「level N で十分」という誤った運用閾値を機械的に再生産する。
#
# 終了コード:
#   0 : 全プローブマーカーがいずれかの level で検出された
#   1 : どの level でも検出されなかったマーカーがある（プローブ or 環境の劣化）
#   2 : 設定ミス・実行不能（引数不正、phpstan/jq 未検出、検体0件、PHPStan の実行不能）

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=lib/find-bin.sh disable=SC1091
. "${SCRIPT_DIR}/lib/find-bin.sh"

PROBE_DIR="${SCRIPT_DIR}/probes/phpstan"
PHP_VERSION=""
LEVELS=""
FORMAT="table"
PHPSTAN_BIN=""
MEMORY_LIMIT="1G"

while [ "$#" -gt 0 ]; do
  arg="$1"
  shift
  case "${arg}" in
    --probe-dir=*)    PROBE_DIR="${arg#--probe-dir=}" ;;
    --php-version=*)  PHP_VERSION="${arg#--php-version=}" ;;
    --levels=*)       LEVELS="${arg#--levels=}" ;;
    --format=*)       FORMAT="${arg#--format=}" ;;
    --phpstan=*)      PHPSTAN_BIN="${arg#--phpstan=}" ;;
    --memory-limit=*) MEMORY_LIMIT="${arg#--memory-limit=}" ;;
    -h|--help)
      sed -n '2,26p' "$0" >&2
      exit 2
      ;;
    *)
      printf 'Error: 不明な引数です: %s\n' "${arg}" >&2
      printf '  引数は --key=value 形式です。位置引数は受け付けません。\n' >&2
      exit 2
      ;;
  esac
done

# ---- 引数検証（S4: 外部ツールへ素通しせず、ここで書式を確定させる） ----

# --php-version を省略時に既定値を捏造しない。SKILL.md の `--to` と同じ思想。
if [ -z "${PHP_VERSION}" ]; then
  cat >&2 <<'EOF'
Error: --php-version=<x.y> を指定してください（例: --php-version=8.3）。
  既定値は設けていません。測定対象のバージョンを取り違えると、
  出力表の下限 level がそのまま誤った運用閾値になります。
EOF
  exit 2
fi

if ! printf '%s' "${PHP_VERSION}" | grep -qE '^[0-9]+\.[0-9]+$'; then
  printf 'Error: --php-version の書式が不正です: %s（例: 8.3）\n' "${PHP_VERSION}" >&2
  exit 2
fi

case "${FORMAT}" in
  table|tsv|md) ;;
  *)
    printf 'Error: --format は table / tsv / md のいずれかです: %s\n' "${FORMAT}" >&2
    exit 2
    ;;
esac

LEVEL_MIN=0
LEVEL_MAX=""
LEVELS_EXPLICIT=0
if [ -n "${LEVELS}" ]; then
  if ! printf '%s' "${LEVELS}" | grep -qE '^[0-9]+-[0-9]+$'; then
    printf 'Error: --levels の書式が不正です: %s（例: 0-10）\n' "${LEVELS}" >&2
    exit 2
  fi
  LEVEL_MIN="${LEVELS%%-*}"
  LEVEL_MAX="${LEVELS##*-}"
  if [ "${LEVEL_MIN}" -gt "${LEVEL_MAX}" ]; then
    printf 'Error: --levels の下限が上限を超えています: %s\n' "${LEVELS}" >&2
    exit 2
  fi
  LEVELS_EXPLICIT=1
fi

if [ ! -d "${PROBE_DIR}" ]; then
  printf 'Error: 検体ディレクトリがありません: %s\n' "${PROBE_DIR}" >&2
  exit 2
fi
PROBE_DIR="$(cd -- "${PROBE_DIR}" && pwd)"

# ---- 依存ツール ----

if [ -z "${PHPSTAN_BIN}" ]; then
  PHPSTAN_BIN="$(find_bin_require phpstan)" || exit 2
fi
if [ ! -x "${PHPSTAN_BIN}" ] && ! command -v "${PHPSTAN_BIN}" >/dev/null 2>&1; then
  printf 'Error: phpstan を実行できません: %s\n' "${PHPSTAN_BIN}" >&2
  exit 2
fi
JQ_BIN="$(find_bin_require jq path)" || exit 2

# ---- 作業ディレクトリ ----
# C5: rm -rf を変数展開で書かない。mktemp -d の戻り値のみを trap で消す。
TMPD="$(mktemp -d)"
if [ -z "${TMPD}" ] || [ ! -d "${TMPD}" ]; then
  printf 'Error: 一時ディレクトリを作成できませんでした\n' >&2
  exit 2
fi
trap 'rm -rf "${TMPD}"' EXIT INT TERM

MARKERS="${TMPD}/markers.tsv"
HITS="${TMPD}/hits.tsv"
: > "${MARKERS}"
: > "${HITS}"

# ---- 検体からマーカーを収集する ----
# `// @probe-expect <identifier> <variant>` は**直後の1行**に対する期待。
# サイドカーの期待値ファイルは持たない（検体と別ファイルにするとドリフトする）。

probe_count=0
for f in "${PROBE_DIR}"/*.php; do
  [ -f "${f}" ] || continue
  probe_count=$((probe_count + 1))
  # 行頭（インデント可）の `// @probe-expect` のみをマーカーとして読む。
  # ヘッダコメント内でマーカー書式そのものを説明している行を拾わないため。
  grep -nE '^[[:space:]]*// @probe-expect[[:space:]]' "${f}" 2>/dev/null | while IFS= read -r hit; do
    marker_line="${hit%%:*}"
    body="${hit#*:}"
    ident="$(printf '%s' "${body}" | sed -n 's/.*@probe-expect[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p')"
    variant="$(printf '%s' "${body}" | sed -n 's/.*@probe-expect[[:space:]]\{1,\}[^[:space:]]\{1,\}[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p')"
    [ -n "${ident}" ] || continue
    [ -n "${variant}" ] || variant="default"
    printf '%s\t%s\t%s\t%s\n' "${f}" "$((marker_line + 1))" "${ident}" "${variant}" >> "${MARKERS}"
  done
done

if [ "${probe_count}" -eq 0 ]; then
  printf 'Error: 検体が1件もありません: %s/*.php\n' "${PROBE_DIR}" >&2
  printf '  0件のまま「検出0件＝安全」と解釈させないため、ここで停止します。\n' >&2
  exit 2
fi

marker_count=$(wc -l < "${MARKERS}" | tr -d ' ')
if [ "${marker_count}" -eq 0 ]; then
  printf 'Error: 検体に @probe-expect マーカーが1件もありません: %s\n' "${PROBE_DIR}" >&2
  exit 2
fi

# ---- level 総当たり ----
# 一時 neon は printf のみで生成する（C8: ユーザー指定の値を neon へ連結しない）。
# paths は CLI 引数で渡す。tmpDir は level 間で**固定**する
#（level ごとに変えると結果キャッシュが効かず、実測で 9.4 倍遅くなる。design §10.2）。
#
# ★ `reportPossiblyNonexistent*ArrayOffset` は**常に true** で測る。
#   これはスキルが PHPStan 設定の必須項目としているもの（references/detection-gates.md §2
#   「必須パラメータ」）であり、level とは独立した感度である。false のまま測ると
#   形状の無い汎用配列への読み取り（検体 general-array-offset.php）がどの level でも
#   出ず、「level を上げても検出できない＝ツールの限界」と誤読させる。

php_major="${PHP_VERSION%%.*}"
php_minor="${PHP_VERSION##*.}"
php_version_int=$((php_major * 10000 + php_minor * 100))

PHPSTAN_VERSION="$("${PHPSTAN_BIN}" --version 2>/dev/null | head -1 || true)"
[ -n "${PHPSTAN_VERSION}" ] || PHPSTAN_VERSION="(バージョン取得不能)"

level="${LEVEL_MIN}"
detected_max=""
rounded=0
runs=0

while :; do
  if [ "${LEVELS_EXPLICIT}" -eq 1 ] && [ "${level}" -gt "${LEVEL_MAX}" ]; then
    break
  fi
  # 自動探索時の暴走止め。PHPStan の level が将来増えても 30 までは追随する。
  if [ "${LEVELS_EXPLICIT}" -eq 0 ] && [ "${level}" -gt 30 ]; then
    break
  fi

  printf 'parameters:\n    level: %s\n    phpVersion: %s\n    tmpDir: %s\n    reportPossiblyNonexistentGeneralArrayOffset: true\n    reportPossiblyNonexistentConstantArrayOffset: true\n' \
    "${level}" "${php_version_int}" "${TMPD}/cache" > "${TMPD}/probe.neon"

  # S1: set -e 下では `|| exit_code=$?` で明示的に捕捉する。
  # PHPStan は指摘があるだけで 1 を返すため、終了コードを合否に使ってはならない（S2）。
  exit_code=0
  "${PHPSTAN_BIN}" analyse \
    --configuration="${TMPD}/probe.neon" \
    --error-format=json \
    --no-progress \
    --memory-limit="${MEMORY_LIMIT}" \
    "${PROBE_DIR}" > "${TMPD}/out.json" 2> "${TMPD}/err.txt" || exit_code=$?

  # level 設定ファイルが無い＝その level は存在しない。
  # ここで「検出0件」と解釈すると、存在しない level を走らせて緑にする事故になる。
  if grep -qE 'config\.level[0-9]+\.neon' "${TMPD}/out.json" "${TMPD}/err.txt" 2>/dev/null; then
    if [ "${LEVELS_EXPLICIT}" -eq 1 ]; then
      printf '警告: level %s はこの PHPStan に存在しません。上限を %s へ丸めます。\n' \
        "${level}" "$((level - 1))" >&2
      rounded=1
    fi
    detected_max=$((level - 1))
    break
  fi

  # S6: PHPStan は「解析不能」でも exit 1 / stdout 空を返す。
  # stdout が空、または JSON として読めない場合は**合格ではなく判定不能**である。
  if [ ! -s "${TMPD}/out.json" ] || ! "${JQ_BIN}" -e . "${TMPD}/out.json" >/dev/null 2>&1; then
    printf 'Error: PHPStan が level %s で JSON を返しませんでした（exit code: %s）。\n' \
      "${level}" "${exit_code}" >&2
    printf '  プローブ判定不能。合格ではありません。PHPStan の stderr を転記します:\n' >&2
    cat "${TMPD}/err.txt" >&2
    exit 2
  fi

  # C7: ユーザー指定の値は jq フィルタへ文字列連結せず --arg で渡す。
  # shellcheck disable=SC2016
  "${JQ_BIN}" -r --arg L "${level}" \
    '.files // {} | to_entries[] | .key as $f | .value.messages[]
     | "\($f)\t\(.line)\t\(.identifier // "<none>")\t\($L)"' \
    "${TMPD}/out.json" >> "${HITS}"

  runs=$((runs + 1))
  level=$((level + 1))
done

if [ "${runs}" -eq 0 ]; then
  printf 'Error: 1つの level も実行できませんでした（--levels=%s）\n' "${LEVELS}" >&2
  exit 2
fi

if [ "${LEVELS_EXPLICIT}" -eq 1 ] && [ "${rounded}" -eq 0 ]; then
  detected_max="${LEVEL_MAX}"
fi
[ -n "${detected_max}" ] || detected_max="$((level - 1))"

# ---- マーカーと検出結果の突合 ----
# (path, line, identifier) をキーに、最初に検出された level を求める。
# 未検出は `-` として出す。**出力から消さない**（消すと「検出0件＝安全」の再生産になる）。

RESULT="${TMPD}/result.tsv"
# FILENAME で判定する（HITS が空のとき `FNR == NR` は MARKERS に対して真になる）。
awk -F'\t' -v hitsfile="${HITS}" '
  FILENAME == hitsfile {
    key = $1 SUBSEP $2 SUBSEP $3
    lvl = $4 + 0
    if (!(key in minlvl) || lvl < minlvl[key]) { minlvl[key] = lvl }
    next
  }
  {
    key = $1 SUBSEP $2 SUBSEP $3
    if (key in minlvl) { m = minlvl[key] } else { m = "-" }
    # identifier, variant, min_level, path, line
    printf "%s\t%s\t%s\t%s\t%s\n", $3, $4, m, $1, $2
  }
' "${HITS}" "${MARKERS}" > "${RESULT}"

# マーカー行に出た「期待外の identifier」= 期待より多く検出した（design §9.5 → WARN）
EXTRA="${TMPD}/extra.tsv"
awk -F'\t' -v markersfile="${MARKERS}" '
  FILENAME == markersfile { want[$1 SUBSEP $2 SUBSEP $3] = 1; line[$1 SUBSEP $2] = 1; next }
  {
    if (($1 SUBSEP $2) in line && !(($1 SUBSEP $2 SUBSEP $3) in want)) {
      key = $1 SUBSEP $2 SUBSEP $3
      if (!(key in seen) || $4 + 0 < seen[key]) { seen[key] = $4 + 0; p[key] = $1; l[key] = $2; i[key] = $3 }
    }
  }
  END { for (k in seen) { printf "%s\t%s\t%s\t%s\n", i[k], seen[k], p[k], l[k] } }
' "${MARKERS}" "${HITS}" | sort > "${EXTRA}"

missing_count=$(awk -F'\t' '$3 == "-"' "${RESULT}" | wc -l | tr -d ' ')
extra_count=$(wc -l < "${EXTRA}" | tr -d ' ')

# ---- 出力 ----

CAPTION_TOOL="${PHPSTAN_VERSION}"
CAPTION_DATE="$(date +%Y-%m-%d)"

emit_pivot() {
  # $1: md なら Markdown 表、それ以外は整形テキスト
  local mode="$1"
  sort -t$'\t' -k1,1 -k2,2 "${RESULT}" | awk -F'\t' -v mode="${mode}" '
    {
      id = $1; variant = $2; lvl = $3
      cell[id SUBSEP variant] = lvl
      if (!(id in ids)) { ids[id] = 1; order[++n] = id }
      if (variant != "concrete" && variant != "union" && variant != "emixed" && variant != "imixed") {
        extra_variant[id SUBSEP variant] = lvl
        has_extra = 1
      }
    }
    # 未検出セルの表記。テキスト表では ASCII の `-` を使う
    #（`—` は多バイトで printf の桁数計算が byte 単位のため列がずれる）。
    function cellv(id, v, empty) { return ((id SUBSEP v) in cell) ? cell[id SUBSEP v] : empty }
    # 4変種のいずれも持たない identifier は2次元表に載せない（全セルが `—` の行になり読めないため）。
    # それらは下の「その他の変種」表に出るので、情報は落ちない。
    function has_canonical(id) {
      return ((id SUBSEP "concrete") in cell) || ((id SUBSEP "union") in cell) \
          || ((id SUBSEP "emixed") in cell) || ((id SUBSEP "imixed") in cell)
    }
    END {
      if (mode == "md") {
        printf "| identifier | 確定型 | union | explicit mixed | implicit mixed |\n"
        printf "|---|---|---|---|---|\n"
        for (k = 1; k <= n; k++) {
          id = order[k]
          if (!has_canonical(id)) { continue }
          printf "| `%s` | %s | %s | %s | %s |\n", id, cellv(id,"concrete","—"), cellv(id,"union","—"), cellv(id,"emixed","—"), cellv(id,"imixed","—")
        }
      } else {
        printf "%-32s %10s %10s %12s %12s\n", "identifier", "concrete", "union", "explicit-mix", "implicit-mix"
        printf "%-32s %10s %10s %12s %12s\n", "--------------------------------", "----------", "----------", "------------", "------------"
        for (k = 1; k <= n; k++) {
          id = order[k]
          if (!has_canonical(id)) { continue }
          printf "%-32s %10s %10s %12s %12s\n", id, cellv(id,"concrete","-"), cellv(id,"union","-"), cellv(id,"emixed","-"), cellv(id,"imixed","-")
        }
      }
      if (has_extra) {
        if (mode == "md") {
          printf "\n**上記4変種に当てはまらない検体**（型の分かり具合の軸を持たない類型・派生形）:\n\n"
          printf "| identifier | 変種 | 下限 level |\n|---|---|---|\n"
          for (key in extra_variant) {
            split(key, a, SUBSEP)
            printf "| `%s` | %s | %s |\n", a[1], a[2], extra_variant[key]
          }
        } else {
          printf "\nその他の変種（型の分かり具合の軸を持たない類型・派生形）:\n"
          for (key in extra_variant) {
            split(key, a, SUBSEP)
            printf "  %-32s %-10s %s\n", a[1], a[2], extra_variant[key]
          }
        }
      }
    }'
}

case "${FORMAT}" in
  tsv)
    # 1行1マーカー・タブ区切り・ヘッダ無し。未検出は min_level が `-`。
    sort -t$'\t' -k1,1 -k2,2 "${RESULT}"
    ;;
  md)
    # 表の直前に必ず置く3つの文言（design §6.2）。ここを削ると、
    # 表の最小値がそのまま運用閾値として読まれ、本タスクが是正した誤記と同型になる。
    cat <<'EOF'
掲載値は「**なぜ最大 level が必要か**」を示す参考値であり、運用上の閾値ではない。

運用判断の根拠は、プロジェクトごとに `scripts/probe-phpstan-levels.sh` を実行した出力とする。

**この表の最小値を運用閾値にしてはならない。運用閾値は最大値側（implicit mixed 列）で決める。**
レガシーコードは型注釈を持たないため、実コードの下限は常に右端の列である。

EOF
    emit_pivot md
    probe_dir_rel="${PROBE_DIR#"$(dirname "${SCRIPT_DIR}")"/}"
    printf '\n**測定条件**\n\n'
    printf '| 項目 | 値 |\n|---|---|\n'
    printf '| PHPStan | %s |\n' "${CAPTION_TOOL}"
    # shellcheck disable=SC2016
    printf '| `phpVersion` | %s（`--php-version=%s`） |\n' "${php_version_int}" "${PHP_VERSION}"
    printf '| 走査 level 範囲 | %s〜%s |\n' "${LEVEL_MIN}" "${detected_max}"
    printf '| stub 構成 | **なし**（検体自身の PHPDoc から型を作る。プロジェクト非依存） |\n'
    # shellcheck disable=SC2016
    printf '| 必須パラメータ | `reportPossiblyNonexistentGeneralArrayOffset` / `reportPossiblyNonexistentConstantArrayOffset` を true |\n'
    # shellcheck disable=SC2016
    printf '| 検体ディレクトリ | `%s` |\n' "${probe_dir_rel}"
    printf '| マーカー件数 | %s |\n' "${marker_count}"
    printf '| 実行日 | %s |\n' "${CAPTION_DATE}"
    ;;
  table)
    printf 'PHPStan probe: %s / phpVersion=%s / levels %s-%s / probes=%s\n' \
      "${CAPTION_TOOL}" "${php_version_int}" "${LEVEL_MIN}" "${detected_max}" "${PROBE_DIR}"
    printf '必須パラメータ: reportPossiblyNonexistentGeneralArrayOffset / reportPossiblyNonexistentConstantArrayOffset = true\n'
    printf 'マーカー %s 件 / 実行 level 数 %s / 実行日 %s\n\n' "${marker_count}" "${runs}" "${CAPTION_DATE}"
    emit_pivot table
    ;;
esac

# ---- 判定 ----

if [ "${extra_count}" -gt 0 ]; then
  {
    printf '\n[WARN] マーカー行で期待外の identifier も検出されました: %s 件\n' "${extra_count}"
    printf '       問題ではありませんが、検体が意図と違う型に推論されている可能性があります。\n'
    awk -F'\t' '{ printf "       %-36s level %-3s %s:%s\n", $1, $2, $3, $4 }' "${EXTRA}"
  } >&2
fi

if [ "${missing_count}" -gt 0 ]; then
  {
    printf '\n[NG] level %s-%s のいずれでも検出されなかった期待項目: %s 件\n' \
      "${LEVEL_MIN}" "${detected_max}" "${missing_count}"
    awk -F'\t' '$3 == "-" { printf "       %-36s %-10s %s:%s\n", $1, $2, $4, $5 }' "${RESULT}"
    printf '     → 検体の記述か、PHPStan のバージョン/設定を確認してください。\n'
    printf '        **「検出されなかった＝安全」ではありません。**\n'
  } >&2
  exit 1
fi

exit 0
