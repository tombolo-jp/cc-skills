#!/usr/bin/env bash
# 実行時ロガーの LTSV ログを集計する
#
# 使い方:
#   scripts/aggregate-migration-log.sh --log=/var/log/php-migration/site.log
#   scripts/aggregate-migration-log.sh --log=a.log,b.log --group-by=at --format=md
#
# 前提: `scripts/php-migration-logger.php`（または WordPress 版）が出力した LTSV ログ。
#
# 動作:
#   自社コードの箇所ごと（既定）に警告を集計する。
#
#   ★ **「0 件＝安全」を作らせない。**
#     ロガーが起動していなければログは当然空になる。空のログを「警告 0 件」と読むのは、
#     解析できていないものを「指摘 0 件」と読むのと同じ誤りである。
#     したがって **BOOT 行（起動記録）が 1 件も無いログは、集計結果ではなく判定不能**として扱う。
#
# 終了コード:
#   0 : 集計できた（エラー行 0 件でも、BOOT 行があれば 0）
#   1 : 使用しない（このスクリプトは「違反」を判定しない）
#   2 : 入力不正・**BOOT 記録が1件も無い（ロガー未起動の疑い）**

set -euo pipefail
IFS=$'\n\t'

LOGS=""
GROUP_BY="own"
FORMAT="table"
MIN_COUNT=1
SINCE=""
CTX_FILTER=""

while [ "$#" -gt 0 ]; do
  arg="$1"
  shift
  case "${arg}" in
    --log=*)       LOGS="${arg#--log=}" ;;
    --group-by=*)  GROUP_BY="${arg#--group-by=}" ;;
    --format=*)    FORMAT="${arg#--format=}" ;;
    --min-count=*) MIN_COUNT="${arg#--min-count=}" ;;
    --since=*)     SINCE="${arg#--since=}" ;;
    --ctx=*)       CTX_FILTER="${arg#--ctx=}" ;;
    -h|--help)
      sed -n '2,22p' "$0" >&2
      exit 2
      ;;
    *)
      printf 'Error: 不明な引数です: %s\n' "${arg}" >&2
      exit 2
      ;;
  esac
done

if [ -z "${LOGS}" ]; then
  printf 'Error: --log=<file>[,<file>...] を指定してください。\n' >&2
  exit 2
fi

case "${GROUP_BY}" in
  own|at|msg) ;;
  *)
    printf 'Error: --group-by は own / at / msg のいずれかです: %s\n' "${GROUP_BY}" >&2
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

if ! printf '%s' "${MIN_COUNT}" | grep -qE '^[0-9]+$'; then
  printf 'Error: --min-count は整数です: %s\n' "${MIN_COUNT}" >&2
  exit 2
fi

TMPD="$(mktemp -d)"
if [ -z "${TMPD}" ] || [ ! -d "${TMPD}" ]; then
  printf 'Error: 一時ディレクトリを作成できませんでした\n' >&2
  exit 2
fi
trap 'rm -rf "${TMPD}"' EXIT INT TERM

ALL="${TMPD}/all.ltsv"
: > "${ALL}"

log_count=0
_old_ifs="${IFS}"
IFS=','
for f in ${LOGS}; do
  IFS="${_old_ifs}"
  [ -n "${f}" ] || continue
  if [ ! -f "${f}" ]; then
    printf 'Error: ログファイルがありません: %s\n' "${f}" >&2
    printf '  **ファイルが無いことを「警告 0 件」と読まないでください。**\n' >&2
    exit 2
  fi
  cat "${f}" >> "${ALL}"
  log_count=$((log_count + 1))
  IFS=','
done
IFS="${_old_ifs}"

# LTSV を「ラベル→値」で引けるように awk へ渡す。
# 最初の `:` のみを区切りとみなす（値の中の `:` はエスケープしない仕様のため）。
BOOT_COUNT=$(grep -c 'lv:BOOT' "${ALL}" 2>/dev/null || true)
[ -n "${BOOT_COUNT}" ] || BOOT_COUNT=0

ROWS="${TMPD}/rows.tsv"
awk -v group="${GROUP_BY}" -v since="${SINCE}" -v ctxf="${CTX_FILTER}" '
  BEGIN { FS = "\t" }
  {
    delete v
    for (i = 1; i <= NF; i++) {
      p = index($i, ":")
      if (p > 0) { v[substr($i, 1, p - 1)] = substr($i, p + 1) }
    }
    lv = ("lv" in v) ? v["lv"] : ""
    # 集計対象は実際のエラー行のみ。BOOT / HINT / DEDUP は運用情報であって欠陥ではない。
    if (lv == "" || lv == "BOOT" || lv == "HINT" || lv == "DEDUP") { next }
    if (since != "" && ("time" in v) && v["time"] < since) { next }
    if (ctxf != "") {
      ok = 0
      n = split(ctxf, want, ",")
      for (j = 1; j <= n; j++) { if (("ctx" in v) && v["ctx"] == want[j]) { ok = 1 } }
      if (!ok) { next }
    }
    key = (group in v) ? v[group] : "<no-" group ">"
    ctx = ("ctx" in v) ? v["ctx"] : "-"
    sup = ("sup" in v) ? v["sup"] : "-"
    at  = ("at"  in v) ? v["at"]  : "-"
    msg = ("msg" in v) ? v["msg"] : "-"
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", key, lv, ctx, sup, at, msg
  }
' "${ALL}" > "${ROWS}"

error_rows=$(wc -l < "${ROWS}" | tr -d ' ')

# ---- 「0 件＝安全」を作らせない判定 ----

if [ "${BOOT_COUNT}" -eq 0 ] && [ "${error_rows}" -eq 0 ]; then
  {
    printf '[NG] ロガーの起動記録（BOOT 行）がありません。\n'
    printf '     **「0 件＝安全」と解釈しないでください。** これは集計結果ではなく判定不能です。\n'
    printf '     確認すること:\n'
    printf '       1. ロガーが設置されているか（auto_prepend_file / mu-plugin）\n'
    printf '       2. PHP_MIGRATION_EXPIRE の期限が切れていないか\n'
    printf '       3. ログの出力先へ書き込み権限があるか\n'
    printf '       4. scripts/verify-gate.sh --gate=logger が VERIFIED を返すか\n'
  } >&2
  exit 2
fi

if [ "${BOOT_COUNT}" -eq 0 ] && [ "${error_rows}" -gt 0 ]; then
  printf '注記: BOOT 行がありませんが、エラー行はあります。PHP_MIGRATION_BOOT_LOG=0 で\n' >&2
  printf '      運用された可能性があります。集計は続行します。\n' >&2
fi

if [ "${error_rows}" -eq 0 ]; then
  printf '[OK] %s 回の実行で警告 0 件。ロガーは起動していました（BOOT %s 件 / ログ %s 本）。\n' \
    "${BOOT_COUNT}" "${BOOT_COUNT}" "${log_count}"
  exit 0
fi

# own:<unconfigured> が過半を占めるなら、集計の意味が薄いことを先頭で警告する。
unconf=$(awk -F'\t' '$1 == "<unconfigured>"' "${ROWS}" | wc -l | tr -d ' ')
if [ "${unconf}" -gt 0 ] && [ $((unconf * 2)) -gt "${error_rows}" ]; then
  {
    printf '警告: own が <unconfigured> の行が過半（%s/%s）です。\n' "${unconf}" "${error_rows}"
    printf '      PHP_MIGRATION_OWN_PATHS を設定しないと「自社コードのどこを直すか」が出ません。\n'
  } >&2
fi

# ---- 集計 ----

AGG="${TMPD}/agg.tsv"
awk -F'\t' -v minc="${MIN_COUNT}" '
  {
    key = $1
    cnt[key]++
    lvs[key] = lvs[key] (index(lvs[key], $2) ? "" : ($2 " "))
    ctxs[key] = ctxs[key] (index(ctxs[key], $3) ? "" : ($3 " "))
    if ($4 == "1") { sup[key]++ }
    if (!(key in samplemsg)) { samplemsg[key] = $6; sampleat[key] = $5 }
  }
  END {
    for (k in cnt) {
      if (cnt[k] < minc) { continue }
      s = (k in sup) ? sup[k] : 0
      printf "%d\t%s\t%s\t%s\t%d\t%s\t%s\n", cnt[k], k, lvs[k], ctxs[k], s, sampleat[k], samplemsg[k]
    }
  }
' "${ROWS}" | sort -t$'\t' -k1,1nr > "${AGG}"

agg_rows=$(wc -l < "${AGG}" | tr -d ' ')

case "${FORMAT}" in
  tsv)
    cat "${AGG}"
    ;;
  md)
    printf '| 件数 | %s | 種別 | ctx | @抑制 | 代表位置 | 代表メッセージ |\n' "${GROUP_BY}"
    printf '|---:|---|---|---|---:|---|---|\n'
    awk -F'\t' '{ printf "| %s | `%s` | %s | %s | %s | `%s` | %s |\n", $1, $2, $3, $4, $5, $6, $7 }' "${AGG}"
    printf '\n集計対象: エラー行 %s 件 / BOOT %s 件 / ログ %s 本\n' "${error_rows}" "${BOOT_COUNT}" "${log_count}"
    ;;
  table)
    printf 'ロガー集計: エラー行 %s 件 / %s グループ / BOOT %s 件 / ログ %s 本（--group-by=%s）\n\n' \
      "${error_rows}" "${agg_rows}" "${BOOT_COUNT}" "${log_count}" "${GROUP_BY}"
    printf '%6s  %-52s %-14s %s\n' "件数" "${GROUP_BY}" "種別" "代表メッセージ"
    printf '%6s  %-52s %-14s %s\n' "------" "----------------------------------------------------" "--------------" "----------------------"
    awk -F'\t' '{ printf "%6s  %-52s %-14s %s\n", $1, $2, $3, substr($7, 1, 60) }' "${AGG}"
    printf '\n※ 件数は**プロセス内の重複抑制後**の値です。1リクエストで同じ箇所を何度踏んでも\n'
    printf '   1 行に畳まれます（呼び出し元が違えば別行になります）。\n'
    printf '※ 実行時ログに出なかったことは「その箇所が安全」を意味しません。\n'
    printf '   到達しなかっただけの可能性があります。静的解析との突合は\n'
    printf '   scripts/correlate-static-runtime.sh で行ってください。\n'
    ;;
esac

exit 0
