#!/usr/bin/env bash
# ゲートスクリプトの分岐回帰テスト
#
# 使い方:
#   scripts/tests/run-gate-tests.sh
#
# 前提: jq が導入済みであること。PHPStan は**スタブへ差し替える**ため実物は不要。
#
# 動作:
#   `scripts/phpstan-gate.sh` の終了コード分岐を、外部コマンドをスタブに置き換えて
#   すべて実際に実行する。
#
#   ★ `bash -n` と `shellcheck` は必須だが**不十分**である。
#     `set -e` 下の終了コード捕捉漏れも、日本語メッセージ中の `$var）` 形式の展開も、
#     どちらも両方を素通りする（実測確認済み）。**実行以外に検出する方法が無い。**
#     このテストは `exit 2` 系の日本語メッセージ分岐を全て実行させることを目的に含む。
#
#   ★ 最重要ケースは `empty` と `parse` が **2** を返すことである。
#     ここが 0 や 1 に落ちると「解析できていないのに合格」が復活する。
#
# 終了コード:
#   0 : 全ケース期待どおり
#   1 : 期待と異なるケースがある
#   2 : テスト環境の不備（スタブ不在等）

set -euo pipefail
IFS=$'\n\t'

TEST_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
SCRIPTS_DIR="$(cd -- "${TEST_DIR}/.." && pwd)"
GATE="${SCRIPTS_DIR}/phpstan-gate.sh"
STUB="${TEST_DIR}/stubs/phpstan-stub.sh"

if [ ! -x "${GATE}" ]; then
  printf 'Error: ゲートスクリプトが実行可能ではありません: %s\n' "${GATE}" >&2
  exit 2
fi
if [ ! -x "${STUB}" ]; then
  printf 'Error: スタブが実行可能ではありません: %s\n' "${STUB}" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT INT TERM

ROOT="${WORK}/root"
mkdir -p "${ROOT}/src"
printf '<?php\n' > "${ROOT}/src/foo.php"
printf 'parameters:\n    level: 9\n' > "${ROOT}/phpstan.neon"
printf 'offsetAccess.nonOffsetAccessible\nproperty.nonObject\n' > "${ROOT}/ids.txt"
: > "${ROOT}/ids-empty.txt"

TARGET="${ROOT}/src/foo.php"
MSG="Cannot access offset 'k' on array\\|false."

make_ledger() {
  # $1: 出力先 / $2: 状態 / $3: 判定根拠 / $4: meta.level
  cat > "$1" <<LEDGER
# テスト用仕分け台帳

<!-- ledger:meta v1 -->
| キー | 値 |
|---|---|
| kind | phpstan-triage |
| tool | phpstan 2.2.6 |
| level | $4 |
| identifiers | ${ROOT}/ids.txt |
<!-- /ledger:meta -->

<!-- ledger:rows v1 -->
| 状態 | path | identifier | message | count | 根拠種別 | 判定根拠 | 判定関与 | 外部入力起点 | 参考行 |
|---|---|---|---|---|---|---|---|---|---|
| $2 | src/foo.php | offsetAccess.nonOffsetAccessible | ${MSG} | 1 | 到達不能 | $3 | N | N | 12 |
<!-- /ledger:rows -->
LEDGER
}

pass=0
fail=0

run_case() {
  # $1: 説明 / $2: 期待終了コード / 残り: ゲートへの引数（環境変数は呼び出し側で export）
  local desc="$1"; shift
  local expect="$1"; shift
  local actual=0
  local out
  out="$("${GATE}" "$@" 2>&1)" || actual=$?
  if [ "${actual}" -eq "${expect}" ]; then
    printf '  [OK]   %-52s exit=%s\n' "${desc}" "${actual}"
    pass=$((pass + 1))
  else
    printf '  [NG]   %-52s exit=%s（期待 %s）\n' "${desc}" "${actual}" "${expect}"
    printf '%s\n' "${out}" | sed 's/^/         | /'
    fail=$((fail + 1))
  fi
}

printf '=== PHPStan スタブによる5ケース（design §7.10 の最重要回帰テスト） ===\n'

export PHPSTAN_FAKE_FILE="${TARGET}"

PHPSTAN_FAKE=ok run_case "ok     : 指摘なし" 0 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --format=summary

PHPSTAN_FAKE=errors run_case "errors : 未仕分けの指摘あり" 1 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --format=summary

PHPSTAN_FAKE=empty run_case "empty  : stdout 空（★判定不能であって合格ではない）" 2 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --format=summary

PHPSTAN_FAKE=parse run_case "parse  : 構文エラーあり（★解析結果が無効）" 2 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --format=summary

PHPSTAN_FAKE=crash run_case "crash  : 実行時クラッシュ" 2 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --format=summary

printf '\n=== 設定・台帳まわりの exit 2 分岐（S5 の日本語メッセージを実行させる） ===\n'

PHPSTAN_FAKE=ignore run_case "非ファイルエラー（ignore.unmatched）" 2 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --format=summary

PHPSTAN_FAKE=ok run_case "ホワイトリストが空ファイル" 2 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids-empty.txt" --format=summary

PHPSTAN_FAKE=ok run_case "--config が存在しない" 2 \
  --config="${ROOT}/nope.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt"

PHPSTAN_FAKE=ok run_case "--identifiers-file と --identifiers の同時指定" 2 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --identifiers=a.b

PHPSTAN_FAKE=ok run_case "--format が不正" 2 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" --format=xml

PHPSTAN_FAKE=ok run_case "--level の書式が不正" 2 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" --level=abc

PHPSTAN_FAKE=ok run_case "不明な引数" 2 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --bogus=1

PHPSTAN_FAKE=ok run_case "--triage の台帳ファイルが存在しない" 2 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --triage="${ROOT}/nope.md"

printf 'not a ledger\n' > "${WORK}/broken.md"
PHPSTAN_FAKE=errors run_case "台帳にフェンスが無い（★部分的に読んで進めない）" 2 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --triage="${WORK}/broken.md"

make_ledger "${WORK}/badstate.md" "しらべ中" "到達不能であることをコード読解で確認した" 10
PHPSTAN_FAKE=errors run_case "台帳の状態語が未知" 2 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --triage="${WORK}/badstate.md"

make_ledger "${WORK}/shortbasis.md" "偽陽性" "安全" 10
PHPSTAN_FAKE=errors run_case "偽陽性なのに判定根拠が 20 文字未満" 2 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --triage="${WORK}/shortbasis.md"

make_ledger "${WORK}/wronglevel.md" "偽陽性" "到達不能であることをコード読解で確認した" 5
PHPSTAN_FAKE=errors run_case "台帳の測定 level が実行 level と違う" 2 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --triage="${WORK}/wronglevel.md"

printf '\n=== 台帳との突合（合否そのもの） ===\n'

make_ledger "${WORK}/good.md" "偽陽性" "到達不能であることをコード読解で確認した" 10
PHPSTAN_FAKE=errors run_case "仕分け済み → 未仕分け 0 件で合格" 0 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --triage="${WORK}/good.md"

make_ledger "${WORK}/undecided.md" "未判定" "まだ読んでいないので判断できていない" 10
PHPSTAN_FAKE=errors run_case "「未判定」は仕分け済みに数えない" 1 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --triage="${WORK}/undecided.md"

make_ledger "${WORK}/stale.md" "偽陽性" "到達不能であることをコード読解で確認した" 10
PHPSTAN_FAKE=ok run_case "陳腐化のみ → 既定では合格" 0 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --triage="${WORK}/stale.md"

PHPSTAN_FAKE=ok run_case "陳腐化のみ → --strict-ledger で不合格" 1 \
  --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" --root="${ROOT}" \
  --identifiers-file="${ROOT}/ids.txt" --triage="${WORK}/stale.md" --strict-ledger

printf '\n=== 「0 件」の扱い ===\n'

out_zero="$(PHPSTAN_FAKE=ok "${GATE}" --config="${ROOT}/phpstan.neon" --phpstan="${STUB}" \
  --root="${ROOT}" --identifiers-file="${ROOT}/ids.txt" --format=summary 2>&1 || true)"
if printf '%s' "${out_zero}" | grep -q 'verify-gate.sh'; then
  printf '  [OK]   %-52s\n' "0 件のとき verify-gate.sh の案内を必ず出す"
  pass=$((pass + 1))
else
  printf '  [NG]   %-52s\n' "0 件のとき verify-gate.sh の案内が出ていない"
  fail=$((fail + 1))
fi

printf '\n=== 結果 ===\n'
printf '  成功 %s 件 / 失敗 %s 件\n' "${pass}" "${fail}"

if [ "${fail}" -gt 0 ]; then
  exit 1
fi
exit 0
