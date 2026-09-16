#!/usr/bin/env bash
# PHPStan ゲート — 「未仕分けの指摘が 0 件」を合格条件とする
#
# 使い方:
#   scripts/phpstan-gate.sh --config=phpstan.neon --triage=.claude/tasks/xxx/phpstan-triage.md
#   scripts/phpstan-gate.sh --config=phpstan.neon --format=tsv > after.txt
#
# 前提: PHPStan と jq が導入済みであること。台帳は `references/triage-ledger.md` の
#   スキーマ（`<!-- ledger:meta v1 -->` / `<!-- ledger:rows v1 -->`）に従うこと。
#
# 動作:
#   PHPStan の JSON 出力を identifier ホワイトリストで絞り、仕分け台帳との差集合を取る。
#   **合否は「件数 0」ではなく「未仕分け 0 件」で決まる。**
#
#   ★ PHPStan の終了コードを合否に使ってはならない。PHPStan は「違反あり」と
#     「実行不能（対象0件・設定ミス・クラッシュ・メモリ超過）」を区別せず、
#     どちらも exit 1 / stdout 空を返す。**空の出力を「0件＝合格」と読むのが
#     本スクリプトが防ごうとしている失敗そのものである。**
#
# 終了コード:
#   0 : 合格（未仕分けの指摘 0 件）
#   1 : 未仕分けの指摘あり／台帳の陳腐化（--strict-ledger 時）
#   2 : 設定ミス・実行不能・判定不能（PHPStan が JSON を返さない／構文エラーあり／
#       台帳が壊れている／台帳の測定条件が実行時条件と一致しない）

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=lib/find-bin.sh disable=SC1091
. "${SCRIPT_DIR}/lib/find-bin.sh"

CONFIG="phpstan.neon"
LEVEL=""
IDENTIFIERS_FILE=""
IDENTIFIERS_CSV=""
TRIAGE=""
STRICT_LEDGER=0
FORMAT="summary"
OUTPUT=""
ROOT=""
PHPSTAN_BIN=""
MEMORY_LIMIT="1G"

while [ "$#" -gt 0 ]; do
  arg="$1"
  shift
  case "${arg}" in
    --config=*)           CONFIG="${arg#--config=}" ;;
    --level=*)            LEVEL="${arg#--level=}" ;;
    --identifiers-file=*) IDENTIFIERS_FILE="${arg#--identifiers-file=}" ;;
    --identifiers=*)      IDENTIFIERS_CSV="${arg#--identifiers=}" ;;
    --triage=*)           TRIAGE="${arg#--triage=}" ;;
    --strict-ledger)      STRICT_LEDGER=1 ;;
    --format=*)           FORMAT="${arg#--format=}" ;;
    --output=*)           OUTPUT="${arg#--output=}" ;;
    --root=*)             ROOT="${arg#--root=}" ;;
    --phpstan=*)          PHPSTAN_BIN="${arg#--phpstan=}" ;;
    --memory-limit=*)     MEMORY_LIMIT="${arg#--memory-limit=}" ;;
    -h|--help)
      sed -n '2,25p' "$0" >&2
      exit 2
      ;;
    *)
      printf 'Error: 不明な引数です: %s\n' "${arg}" >&2
      printf '  引数は --key=value 形式です。位置引数は受け付けません。\n' >&2
      exit 2
      ;;
  esac
done

# ---- 引数検証（S4） ----

if [ -n "${IDENTIFIERS_FILE}" ] && [ -n "${IDENTIFIERS_CSV}" ]; then
  printf 'Error: --identifiers-file と --identifiers は同時に指定できません。\n' >&2
  exit 2
fi

case "${FORMAT}" in
  summary|tsv|json) ;;
  *)
    printf 'Error: --format は summary / tsv / json のいずれかです: %s\n' "${FORMAT}" >&2
    exit 2
    ;;
esac

if [ -n "${LEVEL}" ] && ! printf '%s' "${LEVEL}" | grep -qE '^([0-9]|[1-9][0-9])$'; then
  printf 'Error: --level の書式が不正です: %s\n' "${LEVEL}" >&2
  exit 2
fi

# --config の既定ファイルが無ければ止まる。**他の neon を探しに行かない。**
if [ ! -f "${CONFIG}" ]; then
  printf 'Error: PHPStan 設定ファイルがありません: %s\n' "${CONFIG}" >&2
  printf '  --config=<path> で明示してください。他の設定ファイルは探索しません。\n' >&2
  exit 2
fi

if [ -z "${ROOT}" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "${ROOT}" ] || ROOT="$(pwd)"
fi
if [ ! -d "${ROOT}" ]; then
  printf 'Error: --root がディレクトリではありません: %s\n' "${ROOT}" >&2
  exit 2
fi
ROOT="$(cd -- "${ROOT}" && pwd)"

if [ -n "${TRIAGE}" ] && [ ! -f "${TRIAGE}" ]; then
  # E2: 台帳が無い＝仕分けしていない。「台帳が無いから全件合格」にしない。
  printf 'Error: 指定された仕分け台帳がありません: %s\n' "${TRIAGE}" >&2
  printf '  台帳が無い状態は「全件未仕分け」です。空の台帳を作るか、--triage を外してください。\n' >&2
  exit 2
fi

# ---- 依存ツール ----

if [ -z "${PHPSTAN_BIN}" ]; then
  PHPSTAN_BIN="$(find_bin_require phpstan)" || exit 2
fi
JQ_BIN="$(find_bin_require jq path)" || exit 2

TMPD="$(mktemp -d)"
if [ -z "${TMPD}" ] || [ ! -d "${TMPD}" ]; then
  printf 'Error: 一時ディレクトリを作成できませんでした\n' >&2
  exit 2
fi
trap 'rm -rf "${TMPD}"' EXIT INT TERM

# ---- identifier ホワイトリストの読み込み ----

IDS_RAW="${TMPD}/ids.txt"
if [ -n "${IDENTIFIERS_CSV}" ]; then
  printf '%s' "${IDENTIFIERS_CSV}" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' > "${IDS_RAW}" || true
else
  if [ -z "${IDENTIFIERS_FILE}" ]; then
    IDENTIFIERS_FILE="${SCRIPT_DIR}/php8-identifiers.txt"
  fi
  if [ ! -f "${IDENTIFIERS_FILE}" ]; then
    printf 'Error: identifier ホワイトリストがありません: %s\n' "${IDENTIFIERS_FILE}" >&2
    exit 2
  fi
  sed 's/#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//' "${IDENTIFIERS_FILE}" | grep -v '^$' > "${IDS_RAW}" || true
fi

ids_count=$(wc -l < "${IDS_RAW}" | tr -d ' ')
if [ "${ids_count}" -eq 0 ]; then
  {
    printf 'Error: identifier ホワイトリストが空です。\n'
    printf '  フィルタが空＝全指摘が対象外になり、このゲートは**必ず合格します**。\n'
    printf '  合格に見えて何も検査していない状態になるため、ここで停止します。\n'
  } >&2
  exit 2
fi

IDS_JSON="$("${JQ_BIN}" -R -s 'split("\n") | map(select(length > 0))' "${IDS_RAW}")"

# ---- level の決定 ----
# D6: 数値を直書きしない。実行時に最大 level を検出する。

# level が存在するかを1回の PHPStan 実行で判定する。
# 「level 設定ファイルが無い」は exit 1 で返るため、終了コードでは区別できない（S2）。
# メッセージで判定する。
_level_exists() {
  local l="$1"
  if ! "${PHPSTAN_BIN}" analyse --no-progress --level="${l}" --error-format=json \
      "${TMPD}/lvlprobe.php" > "${TMPD}/lp.out" 2> "${TMPD}/lp.err"; then
    : # PHPStan は指摘があるだけで非0を返す。ここでは終了コードを判定に使わない。
  fi
  if grep -qE 'config\.level[0-9]+\.neon' "${TMPD}/lp.out" "${TMPD}/lp.err" 2>/dev/null; then
    return 1
  fi
  return 0
}

# 最大 level を実行時に検出する（D6: 数値を直書きしない）。
# level 9 は PHPStan 1.x / 2.x のいずれでも存在するため、そこから上下に探索する。
# 0 から総当たりすると毎回 12 回 PHPStan を起動することになり、
# FR-16「修正のたびに再走査」が現実的な速度で回らなくなる（通常は 3 回で確定する）。
detect_max_level() {
  local l=9
  printf '<?php\n' > "${TMPD}/lvlprobe.php"
  if _level_exists "${l}"; then
    while [ "${l}" -lt 30 ]; do
      if _level_exists "$((l + 1))"; then
        l=$((l + 1))
      else
        break
      fi
    done
    printf '%s\n' "${l}"
    return 0
  fi
  while [ "${l}" -gt 0 ]; do
    l=$((l - 1))
    if _level_exists "${l}"; then
      printf '%s\n' "${l}"
      return 0
    fi
  done
  printf '%s\n' "0"
}

MAX_LEVEL="$(detect_max_level)"
LEVEL_LOWERED=0
if [ -z "${LEVEL}" ]; then
  LEVEL="${MAX_LEVEL}"
elif [ "${LEVEL}" -gt "${MAX_LEVEL}" ]; then
  printf '警告: level %s はこの PHPStan に存在しません。%s へ丸めます。\n' "${LEVEL}" "${MAX_LEVEL}" >&2
  LEVEL="${MAX_LEVEL}"
elif [ "${LEVEL}" -lt "${MAX_LEVEL}" ]; then
  # 明示的に下げた場合は黙って受け入れない。取りこぼしがあることを必ず表に出す。
  LEVEL_LOWERED=1
  printf '警告: level %s で判定します（この PHPStan の最大は %s）。取りこぼしがあります。\n' \
    "${LEVEL}" "${MAX_LEVEL}" >&2
fi

# ---- PHPStan の実行 ----

exit_code=0
"${PHPSTAN_BIN}" analyse \
  --configuration="${CONFIG}" \
  --level="${LEVEL}" \
  --error-format=json \
  --no-progress \
  --memory-limit="${MEMORY_LIMIT}" \
  > "${TMPD}/out.json" 2> "${TMPD}/err.txt" || exit_code=$?

# ★S6: stdout が空、または JSON として読めない → **合格ではなく判定不能**。
if [ ! -s "${TMPD}/out.json" ] || ! "${JQ_BIN}" -e . "${TMPD}/out.json" >/dev/null 2>&1; then
  {
    printf 'Error: PHPStan が JSON を返しませんでした（exit code: %s）。\n' "${exit_code}"
    printf '  **ゲート判定不能。合格ではありません。**\n'
    printf '  PHPStan は対象0件・設定ミス・クラッシュ・メモリ超過のいずれでも\n'
    printf '  exit 1 / 出力空を返すため、この状態を「指摘0件」と読んではいけません。\n'
    printf '  ---- PHPStan の stderr ----\n'
    cat "${TMPD}/err.txt"
  } >&2
  exit 2
fi

# 非ファイルエラー（ignore.unmatched / ignore.count 等）。
# ignoreErrors / baseline が実態と食い違っている＝**観測結果の網羅性が保証されない**。
# 合否を出さず判定不能とする（区別のため MAINTENANCE と表示する）。
non_file_errors="$("${JQ_BIN}" -r '.errors // [] | length' "${TMPD}/out.json")"
if [ "${non_file_errors}" -gt 0 ]; then
  {
    printf '[MAINTENANCE] 非ファイルエラーが %s 件あります。ゲート判定不能です。\n' "${non_file_errors}"
    "${JQ_BIN}" -r '.errors[] | "  - \(.)"' "${TMPD}/out.json"
    printf '  ignoreErrors / baseline が実態と食い違っています。\n'
    printf '  これは「違反」ではなく設定の陳腐化ですが、**観測結果を信頼できないため合格にしません**。\n'
    # shellcheck disable=SC2016
    printf '  `reportUnmatchedIgnoredErrors: false` で消さないこと（陳腐化が検出されなくなります）。\n'
  } >&2
  exit 2
fi

# ★M5: 構文エラーのあるファイルがある＝そのファイルの解析結果は無効。
parse_errors="$("${JQ_BIN}" -r '[.files // {} | .[].messages[] | select(.identifier == "phpstan.parse")] | length' "${TMPD}/out.json")"
if [ "${parse_errors}" -gt 0 ]; then
  {
    printf 'Error: 構文エラーのあるファイルがあります（%s 件）。\n' "${parse_errors}"
    printf '  **解析結果は無効です。0 件を根拠にしないでください。**\n'
    # shellcheck disable=SC2016
    "${JQ_BIN}" -r '.files // {} | to_entries[] | .key as $f | .value.messages[]
                    | select(.identifier == "phpstan.parse") | "  - \($f):\(.line) \(.message)"' "${TMPD}/out.json"
  } >&2
  exit 2
fi

# ---- 検出キーの生成（§6.3 のキー設計: path + identifier + 正規化 message） ----
# 行番号はキーに含めない。修正のたびにずれ、台帳が全件無効化されるため。

DETECT_TSV="${TMPD}/detect.tsv"
# C7: ユーザー指定の identifier を jq フィルタへ連結せず --argjson で渡す。
# shellcheck disable=SC2016
"${JQ_BIN}" -r --argjson ids "${IDS_JSON}" --arg root "${ROOT}/" '
  def norm_msg:
    gsub("\\s+"; " ")
    | sub("^ +"; "") | sub(" +$"; "")
    | gsub("\\{[^{}]*\\}"; "{...}")
    | gsub("\\{[^{}]*\\}"; "{...}");
  def keep($id): $ids | any(
    . as $p | if ($p | endswith("*")) then ($id | startswith($p[:-1])) else $id == $p end
  );
  [ .files // {} | to_entries[] | .key as $f | .value.messages[]
    | select(.identifier != null) | select(keep(.identifier))
    | { path: (if ($f | startswith($root)) then ($f | ltrimstr($root)) else $f end),
        identifier: .identifier,
        message: (.message | norm_msg),
        line: .line } ]
  | group_by(.path + " " + .identifier + " " + .message)
  | map({ path: .[0].path, identifier: .[0].identifier, message: .[0].message,
          count: length, lines: (map(.line | tostring) | join(",")) })
  | sort_by(.path, .identifier, .message)[]
  | [.path, .identifier, .message, (.count | tostring), .lines] | @tsv
' "${TMPD}/out.json" > "${DETECT_TSV}"

detect_rows=$(wc -l < "${DETECT_TSV}" | tr -d ' ')
detect_total=$(awk -F'\t' '{ s += $4 } END { printf "%d", s + 0 }' "${DETECT_TSV}")

# ---- 台帳の読み込みと検証 ----

LEDGER_TSV="${TMPD}/ledger.tsv"
: > "${LEDGER_TSV}"
ledger_rows=0
ledger_fixed=0
ledger_fp=0
ledger_hold=0
ledger_undecided=0

if [ -n "${TRIAGE}" ]; then
  # フェンスの検証。見出しの改名でパーサが壊れないよう、機械判定はフェンス内のみを読む。
  if ! grep -qE '^<!-- ledger:rows v1 -->[[:space:]]*$' "${TRIAGE}"; then
    {
      # shellcheck disable=SC2016
      printf 'Error: 台帳に `<!-- ledger:rows v1 -->` フェンスがありません: %s\n' "${TRIAGE}"
      printf '  **BLOCK。** 壊れた台帳で突合すると、一部が黙って未仕分け扱いを免れます。\n'
      printf '  スキーマは references/triage-ledger.md §1 を参照してください。\n'
    } >&2
    exit 2
  fi
  if grep -qE '^<!-- ledger:(meta|rows) v([2-9]|[1-9][0-9]) -->[[:space:]]*$' "${TRIAGE}"; then
    printf 'Error: 台帳のスキーマバージョンが未知です（v1 のみ対応）: %s\n' "${TRIAGE}" >&2
    exit 2
  fi

  # --- meta ブロックの照合（§9.3: 測定条件が違う台帳を「仕分け済み」として通さない） ---
  META_TSV="${TMPD}/meta.tsv"
  # ★ フェンスは**行全体が一致**するときだけ認識する。
  #   部分一致にすると、台帳の説明文がフェンス文字列を引用しているだけで
  #   そこからブロックが始まったことになり、meta 表の行が rows として読まれる。
  awk '
    /^<!-- ledger:meta v1 -->[[:space:]]*$/ { inmeta = 1; next }
    /^<!-- \/ledger:meta -->[[:space:]]*$/  { inmeta = 0; next }
    inmeta && /^\|/ {
      line = $0
      gsub(/^\|[[:space:]]*/, "", line)
      gsub(/[[:space:]]*\|[[:space:]]*$/, "", line)
      n = split(line, c, /[[:space:]]*\|[[:space:]]*/)
      if (n >= 2 && c[1] != "キー" && c[1] !~ /^-+$/) { printf "%s\t%s\n", c[1], c[2] }
    }
  ' "${TRIAGE}" > "${META_TSV}"

  meta_get() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "${META_TSV}"; }

  meta_tool="$(meta_get tool)"
  meta_level="$(meta_get level)"
  meta_ids="$(meta_get identifiers)"

  phpstan_ver_full="$("${PHPSTAN_BIN}" --version 2>/dev/null | head -1 || true)"
  phpstan_ver_num="$(printf '%s' "${phpstan_ver_full}" | sed -n 's/.*[^0-9]\([0-9]\{1,\}\.[0-9]\{1,\}\.[0-9]\{1,\}\).*/\1/p')"

  # E6: identifier 名はツールのバージョンで変わりうる。台帳が全滅した状態を
  #     「新規100件」と誤読させない。
  if [ -n "${meta_tool}" ] && [ -n "${phpstan_ver_num}" ]; then
    meta_tool_num="$(printf '%s' "${meta_tool}" | sed -n 's/.*[^0-9]\{0,\}\([0-9]\{1,\}\.[0-9]\{1,\}\.[0-9]\{1,\}\).*/\1/p')"
    if [ -n "${meta_tool_num}" ] && [ "${meta_tool_num}" != "${phpstan_ver_num}" ]; then
      {
        printf 'Error: 台帳の測定ツールと現行 PHPStan のバージョンが異なります。\n'
        printf '  台帳 meta.tool : %s\n' "${meta_tool}"
        printf '  現行 phpstan   : %s\n' "${phpstan_ver_full}"
        printf '  **BLOCK。** identifier マッピングの確認が必要です。\n'
        printf '  バージョン差で identifier 名が変わると、台帳が全滅して「新規大量発生」に見えます。\n'
      } >&2
      exit 2
    fi
  fi

  # §9.3: level が違う台帳を通すと「level 5 で 0 件」を「問題なし」と読み替えた失敗が、
  #       台帳という新しい皮をかぶって再発する。
  if [ -n "${meta_level}" ] && [ "${meta_level}" != "${LEVEL}" ]; then
    {
      printf 'Error: 台帳の測定 level（%s）と実行 level（%s）が一致しません。\n' "${meta_level}" "${LEVEL}"
      printf '  **合否を出しません（判定不能）。** 台帳は測定条件とセットでしか意味を持ちません。\n'
      printf '  台帳を再作成するか、--level=%s を指定してください。\n' "${meta_level}"
    } >&2
    exit 2
  fi

  # E7: ホワイトリストを変更した場合は、変更内容を報告してから突合する（WARN）。
  if [ -n "${meta_ids}" ]; then
    eff_ids="${IDENTIFIERS_FILE:-（--identifiers による直接指定）}"
    eff_ids_rel="${eff_ids#"${ROOT}"/}"
    if [ "${meta_ids}" != "${eff_ids}" ] && [ "${meta_ids}" != "${eff_ids_rel}" ]; then
      printf '警告: 台帳の meta.identifiers（%s）と実行時のホワイトリスト（%s）が異なります。\n' \
        "${meta_ids}" "${eff_ids_rel}" >&2
      printf '  外した identifier があるなら「なぜ外したか」を記録してください。\n' >&2
    fi
  fi

  # --- rows ブロックの読み込みと検証 ---
  ROWS_RAW="${TMPD}/rows.raw"
  awk '
    /^<!-- ledger:rows v1 -->[[:space:]]*$/ { inrows = 1; rowno = 0; next }
    /^<!-- \/ledger:rows -->[[:space:]]*$/  { inrows = 0; next }
    inrows { rowno++; if ($0 ~ /^\|/) { printf "%d\t%s\n", FNR, $0 } }
  ' "${TRIAGE}" > "${ROWS_RAW}"

  # セル内の `\|` はエスケープ。直前が `\` でない `|` で分割し、その後アンエスケープする。
  # 判定根拠の文字数は**コードポイント**で数える（バイト数で数えると日本語で誤判定する）。
  ROWS_JSON="${TMPD}/rows.json"
  # shellcheck disable=SC2016
  "${JQ_BIN}" -R -s '
    def unesc: gsub("\\\\\\|"; "@@PIPE@@") ;
    def split_cells: unesc | split("|") | map(gsub("@@PIPE@@"; "|"));
    def norm_msg:
      gsub("`"; "") | gsub("\\*\\*"; "")
      | gsub("\\s+"; " ") | sub("^ +"; "") | sub(" +$"; "")
      | gsub("\\{[^{}]*\\}"; "{...}")
      | gsub("\\{[^{}]*\\}"; "{...}");
    split("\n") | map(select(length > 0))
    | map(
        (split("\t")) as $p
        | { lineno: ($p[0] | tonumber), raw: ($p[1:] | join("\t")) }
      )
    | map(. + { cells: (.raw | split_cells | map(gsub("^\\s+|\\s+$"; ""))) })
    | map(select((.cells | length) > 3))
    | map(select((.cells[1] // "") != "状態"))
    | map(select((.cells[1] // "") | test("^-+$") | not))
    | map({
        lineno: .lineno,
        state:      (.cells[1] // ""),
        path:       (.cells[2] // "" | gsub("`"; "") | gsub("^\\s+|\\s+$"; "")),
        identifier: (.cells[3] // "" | gsub("`"; "") | gsub("^\\s+|\\s+$"; "")),
        message:    (.cells[4] // "" | norm_msg),
        count:      (.cells[5] // ""),
        basis_kind: (.cells[6] // ""),
        basis:      (.cells[7] // "")
      })
  ' "${ROWS_RAW}" > "${ROWS_JSON}"

  # 書式違反の検査（行番号つきで指摘する）
  FMT_ERR="${TMPD}/fmterr.txt"
  # shellcheck disable=SC2016
  "${JQ_BIN}" -r '
    .[] | select(
      # `["…"] | index(.state)` と書くとパイプの右側で `.` が配列に切り替わり、
      # `.state` が「配列を文字列で添字」になって実行時エラーになる。状態語を先に束縛する。
      .state as $s | ["未判定","対応済","偽陽性","保留"] | index($s) == null
    ) | "  L\(.lineno): 未知の状態語 「\(.state)」（使えるのは 未判定 / 対応済 / 偽陽性 / 保留）"
  ' "${ROWS_JSON}" > "${FMT_ERR}"
  # shellcheck disable=SC2016
  "${JQ_BIN}" -r '
    .[] | select(.state == "偽陽性") | select((.basis | length) < 20)
    | "  L\(.lineno): 偽陽性の判定根拠が \(.basis | length) 文字です（20 文字以上必要）: \(.path) \(.identifier)"
  ' "${ROWS_JSON}" >> "${FMT_ERR}"

  if [ -s "${FMT_ERR}" ]; then
    {
      printf 'Error: 仕分け台帳が書式違反です: %s\n' "${TRIAGE}"
      cat "${FMT_ERR}"
      printf '  **BLOCK。** 根拠の無い偽陽性判定を構造として認めません。\n'
    } >&2
    exit 2
  fi

  # 判定根拠が 20 文字未満の行は、状態の値によらず**未仕分け扱い**にする。
  # shellcheck disable=SC2016
  "${JQ_BIN}" -r '
    .[] | [ .path, .identifier, .message,
            (if (.basis | length) < 20 then "未判定" else .state end),
            .count, (.lineno | tostring) ] | @tsv
  ' "${ROWS_JSON}" | sort > "${LEDGER_TSV}"

  ledger_rows=$(wc -l < "${LEDGER_TSV}" | tr -d ' ')
  ledger_fixed=$(awk -F'\t' '$4 == "対応済"' "${LEDGER_TSV}" | wc -l | tr -d ' ')
  ledger_fp=$(awk -F'\t' '$4 == "偽陽性"' "${LEDGER_TSV}" | wc -l | tr -d ' ')
  ledger_hold=$(awk -F'\t' '$4 == "保留"' "${LEDGER_TSV}" | wc -l | tr -d ' ')
  ledger_undecided=$(awk -F'\t' '$4 == "未判定"' "${LEDGER_TSV}" | wc -l | tr -d ' ')
fi

# ---- 差集合 ----
# S3: bash 3.2 に連想配列は無い。キーの差集合は comm でストリーム処理する。

DETECT_KEYS="${TMPD}/detect.keys"
LEDGER_KEYS="${TMPD}/ledger.keys"
awk -F'\t' '{ printf "%s %s %s\n", $1, $2, $3 }' "${DETECT_TSV}" | sort > "${DETECT_KEYS}"
# 「未判定」は仕分け済みに数えない。行だけ足して通す抜け道を塞ぐ。
awk -F'\t' '$4 != "未判定" { printf "%s %s %s\n", $1, $2, $3 }' "${LEDGER_TSV}" | sort > "${LEDGER_KEYS}"

UNTRIAGED_KEYS="${TMPD}/untriaged.keys"
STALE_KEYS="${TMPD}/stale.keys"
comm -23 "${DETECT_KEYS}" "${LEDGER_KEYS}" > "${UNTRIAGED_KEYS}"
comm -13 "${DETECT_KEYS}" "${LEDGER_KEYS}" > "${STALE_KEYS}"

untriaged_count=$(wc -l < "${UNTRIAGED_KEYS}" | tr -d ' ')
stale_count=$(wc -l < "${STALE_KEYS}" | tr -d ' ')

# count の増減（E9: NOTICE。FAIL にしない）
COUNT_DRIFT="${TMPD}/countdrift.tsv"
: > "${COUNT_DRIFT}"
if [ "${ledger_rows}" -gt 0 ]; then
  awk -F'\t' -v ledger="${LEDGER_TSV}" '
    FILENAME == ledger { lc[$1 SUBSEP $2 SUBSEP $3] = $5; next }
    {
      k = $1 SUBSEP $2 SUBSEP $3
      if (k in lc && lc[k] != "" && lc[k] ~ /^[0-9]+$/ && lc[k] + 0 != $4 + 0) {
        printf "%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, lc[k], $4
      }
    }
  ' "${LEDGER_TSV}" "${DETECT_TSV}" > "${COUNT_DRIFT}"
fi
count_drift=$(wc -l < "${COUNT_DRIFT}" | tr -d ' ')

# ---- 出力 ----

CLASSIFIED="${TMPD}/classified.tsv"
# ★ 2ファイルを読む awk で `FNR == NR` を「1つ目のファイル」の判定に使ってはならない。
#   1つ目が**空ファイル**のとき、その条件は2つ目のファイルに対して真になり、
#   台帳が空（＝初回実行で全件が未仕分けであるべき状況）で**出力が丸ごと消える**。
#   FILENAME で明示的に判定する。
awk -F'\t' -v ledger="${LEDGER_TSV}" '
  FILENAME == ledger { st[$1 SUBSEP $2 SUBSEP $3] = $4; next }
  {
    k = $1 SUBSEP $2 SUBSEP $3
    s = (k in st) ? st[k] : "未判定"
    if (s == "対応済")      { tag = "TRIAGED_FIXED" }
    else if (s == "偽陽性") { tag = "TRIAGED_FP" }
    else if (s == "保留")   { tag = "TRIAGED_HOLD" }
    else                    { tag = "UNTRIAGED" }
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", tag, $1, $2, $3, $4, $5
  }
' "${LEDGER_TSV}" "${DETECT_TSV}" > "${CLASSIFIED}"
if [ "${stale_count}" -gt 0 ]; then
  awk -F'\t' -v stalefile="${STALE_KEYS}" '
    FILENAME == stalefile { stale[$0] = 1; next }
    { k = $1 " " $2 " " $3; if (k in stale) printf "STALE\t%s\t%s\t%s\t%s\t\n", $1, $2, $3, $5 }
  ' "${STALE_KEYS}" "${LEDGER_TSV}" >> "${CLASSIFIED}"
fi

emit() {
  case "${FORMAT}" in
    tsv)
      sort "${CLASSIFIED}"
      ;;
    json)
      # shellcheck disable=SC2016
      "${JQ_BIN}" -R -s --arg level "${LEVEL}" --arg max "${MAX_LEVEL}" \
        --arg untriaged "${untriaged_count}" --arg stale "${stale_count}" '
        { level: ($level | tonumber), max_level: ($max | tonumber),
          untriaged: ($untriaged | tonumber), stale: ($stale | tonumber),
          rows: (split("\n") | map(select(length > 0)) | map(split("\t"))
                 | map({ status: .[0], path: .[1], identifier: .[2],
                         message: .[3], count: .[4], lines: .[5] })) }
      ' "${CLASSIFIED}"
      ;;
    summary)
      printf 'PHPStan gate: level=%s（最大 %s） / config=%s / %s\n' \
        "${LEVEL}" "${MAX_LEVEL}" "${CONFIG}" "${PHPSTAN_VERSION_LINE}"
      if [ "${LEVEL_LOWERED}" -eq 1 ]; then
        printf '  ★ level %s で判定（最大より低い。取りこぼしがあります）\n' "${LEVEL}"
      fi
      printf 'identifier whitelist: %s (%s entries)\n' \
        "${IDENTIFIERS_FILE:-（--identifiers による直接指定）}" "${ids_count}"
      if [ -n "${TRIAGE}" ]; then
        printf 'triage ledger: %s (%s entries / 対応済 %s, 偽陽性 %s, 保留 %s, 未判定 %s)\n' \
          "${TRIAGE}" "${ledger_rows}" "${ledger_fixed}" "${ledger_fp}" "${ledger_hold}" "${ledger_undecided}"
      else
        printf 'triage ledger: **未指定**（全指摘を未仕分けとして扱います）\n'
      fi
      printf '\n'

      if [ "${untriaged_count}" -eq 0 ]; then
        printf '[OK] 未仕分けの指摘: 0 件\n'
      else
        printf '[NG] 未仕分けの指摘: %s 件\n\n' "${untriaged_count}"
        awk -F'\t' '$1 == "UNTRIAGED" {
          printf "  %s\n    %-36s %s\n    L%s（参考行。突合キーには使いません）\n", $2, $3, $4, $6
        }' "${CLASSIFIED}"
        printf '\n  → 1件ずつ「偽陽性」「実対応要」を判定し、根拠つきで台帳へ追記してください。\n'
        printf '     判定不能なら「未判定」のまま残してエスカレーションすること。**偽陽性へ倒さない。**\n'
      fi

      printf '\n[i] 観測 %s 件（%s キー） / 仕分け済み %s キー\n' \
        "${detect_total}" "${detect_rows}" "$((detect_rows - untriaged_count))"

      if [ "${count_drift}" -gt 0 ]; then
        printf '[NOTICE] count が台帳と異なるエントリ: %s 件（FAIL にはしません）\n' "${count_drift}"
        awk -F'\t' '{ printf "  %s %s: 記録時 %s 件 → 現在 %s 件\n", $1, $2, $4, $5 }' "${COUNT_DRIFT}"
        printf '  → 新しい出現箇所が同じ判定でよいか確認してください。\n'
      fi

      if [ "${stale_count}" -gt 0 ]; then
        printf '[WARN] 陳腐化した台帳エントリ: %s 件' "${stale_count}"
        if [ "${STRICT_LEDGER}" -eq 1 ]; then
          printf '（--strict-ledger により FAIL 扱い）\n'
        else
          printf '（--strict-ledger で FAIL 扱いになります）\n'
        fi
        awk -F'\t' '{ split($0, a, " "); printf "  %s %s\n", a[1], a[2] }' "${STALE_KEYS}"
        # shellcheck disable=SC2016
        printf '  → 台帳から**削除しないこと**。`resolved: <日付>` と消えた理由を1行書いて残す。\n'
        printf '     黙って消すと、あとで再発したときに「初めて出た」と誤認します。\n'
      fi

      if [ "${detect_rows}" -eq 0 ] && [ "${ledger_rows}" -eq 0 ]; then
        printf '\n[!] フィルタ後 0 件、かつ台帳も 0 件です。\n'
        # shellcheck disable=SC2016
        printf '    **このゲートが実際に機能しているかを `scripts/verify-gate.sh --gate=phpstan` で確認してください。**\n'
        printf '    検証していないゲートの「0 件」は合格ではありません（NOT-RUN と同義）。\n'
      fi
      ;;
  esac
}

PHPSTAN_VERSION_LINE="$("${PHPSTAN_BIN}" --version 2>/dev/null | head -1 || true)"
[ -n "${PHPSTAN_VERSION_LINE}" ] || PHPSTAN_VERSION_LINE="(バージョン取得不能)"

if [ -n "${OUTPUT}" ]; then
  emit > "${OUTPUT}"
else
  emit
fi

# ---- 判定 ----

if [ "${untriaged_count}" -gt 0 ]; then
  exit 1
fi
if [ "${STRICT_LEDGER}" -eq 1 ] && [ "${stale_count}" -gt 0 ]; then
  exit 1
fi
exit 0
