#!/usr/bin/env bash
# PHPStan のスタブ（回帰テスト専用。本番の解析には使わない）
#
# 使い方:
#   PHPSTAN_FAKE=empty scripts/tests/stubs/phpstan-stub.sh analyse --error-format=json ...
#
# 前提: `scripts/phpstan-gate.sh --phpstan=<このファイル>` から呼ばれる。
#
# 動作: 環境変数 `PHPSTAN_FAKE` に応じて PHPStan の実挙動を再現する。
#   ok     : 指摘なし（JSON あり・exit 0）
#   errors : ホワイトリスト該当の指摘 1 件（JSON あり・exit 1）
#   empty  : **stdout 空 + exit 1**（対象0件 / 設定ミス / クラッシュ / メモリ超過の実挙動）
#   parse  : 構文エラー（phpstan.parse を含む JSON・exit 1）
#   crash  : stderr にメッセージ + exit 255
#   ignore : 非ファイルエラー（ignore.unmatched）を含む JSON・exit 1
#
#   `--version` と level 探索用の呼び出しは PHPSTAN_FAKE によらず常に成功させる
#   （テスト対象はゲートの判定分岐であって level 探索ではないため）。
#
# 終了コード: 上記のとおり PHPStan の実挙動を模倣する。合否の意味は持たない。

set -euo pipefail

ARGS="$*"

if printf '%s' "${ARGS}" | grep -q -- '--version'; then
  printf 'PHPStan - PHP Static Analysis Tool 2.2.6\n'
  exit 0
fi

# level 探索の呼び出し（lvlprobe.php を対象にしたもの）。
# この PHPStan の最大 level は 10 という設定で応答する。
if printf '%s' "${ARGS}" | grep -q 'lvlprobe\.php'; then
  lvl="$(printf '%s' "${ARGS}" | sed -n 's/.*--level=\([0-9]\{1,\}\).*/\1/p')"
  [ -n "${lvl}" ] || lvl=0
  if [ "${lvl}" -gt 10 ]; then
    printf 'Level config file phar:///stub/conf/config.level%s.neon was not found.\n' "${lvl}"
    exit 1
  fi
  printf '{"totals":{"errors":0,"file_errors":0},"files":{},"errors":[]}\n'
  exit 0
fi

FAKE="${PHPSTAN_FAKE:-ok}"
TARGET_FILE="${PHPSTAN_FAKE_FILE:-/tmp/stub-root/src/foo.php}"

case "${FAKE}" in
  ok)
    printf '{"totals":{"errors":0,"file_errors":0},"files":{},"errors":[]}\n'
    exit 0
    ;;
  errors)
    cat <<JSON
{"totals":{"errors":0,"file_errors":1},
 "files":{"${TARGET_FILE}":{"errors":1,"messages":[
   {"message":"Cannot access offset 'k' on array|false.","line":12,"ignorable":true,"identifier":"offsetAccess.nonOffsetAccessible"}
 ]}},
 "errors":[]}
JSON
    exit 1
    ;;
  empty)
    # ★ 本スタブの中核。PHPStan は「解析不能」でも exit 1 / stdout 空を返す。
    #    ここが 0 や 1 と判定されると、本スキルが防ごうとしている失敗が再発する。
    printf 'Configuration error or no files found.\n' >&2
    exit 1
    ;;
  parse)
    cat <<JSON
{"totals":{"errors":0,"file_errors":1},
 "files":{"${TARGET_FILE}":{"errors":1,"messages":[
   {"message":"Syntax error, unexpected T_STRING on line 3","line":3,"ignorable":false,"identifier":"phpstan.parse"}
 ]}},
 "errors":[]}
JSON
    exit 1
    ;;
  ignore)
    cat <<'JSON'
{"totals":{"errors":1,"file_errors":0},
 "files":{},
 "errors":["Ignored error pattern return.unusedType was not matched in reported errors."]}
JSON
    exit 1
    ;;
  crash)
    printf 'PHP Fatal error: Allowed memory size exhausted\n' >&2
    exit 255
    ;;
  *)
    printf 'stub: 未知の PHPSTAN_FAKE です: %s\n' "${FAKE}" >&2
    exit 3
    ;;
esac
