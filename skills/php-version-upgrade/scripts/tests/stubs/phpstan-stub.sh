#!/usr/bin/env bash
# PHPStan のスタブ（回帰テスト専用。本番の解析には使わない）
#
# 使い方:
#   PHPSTAN_FAKE=empty scripts/tests/stubs/phpstan-stub.sh analyse --error-format=json ...
#
# 前提: `scripts/phpstan-gate.sh` / `scripts/verify-gate.sh` / `scripts/probe-phpstan-levels.sh` の
#   `--phpstan=<このファイル>` から呼ばれる。
#
# 動作: 環境変数 `PHPSTAN_FAKE` に応じて PHPStan の実挙動を再現する。
#   ok     : 指摘なし（JSON あり・exit 0）
#   errors : ホワイトリスト該当の指摘 1 件（JSON あり・exit 1）
#   empty  : **stdout 空 + exit 1**（対象0件 / 設定ミス / クラッシュ / メモリ超過の実挙動）
#   parse  : 構文エラー（phpstan.parse を含む JSON・exit 1）
#   crash  : stderr にメッセージ + exit 255
#   ignore : 非ファイルエラー（ignore.unmatched）を含む JSON・exit 1
#
#   ---- verify-gate.sh --gate=phpstan 用 ----
#   verify          : 解析対象ファイル（パス引数の .php、無ければ PHPSTAN_FAKE_PLANT_DIR 内の
#                     `__gate_probe_*.php`）に 1 件の指摘を出す。加えて `// @gate-require <id>` の
#                     直後の行に <id> を出す。**ただし neon に
#                     `reportPossiblyNonexistentGeneralArrayOffset: true` がある場合のみ**
#                     （実物の PHPStan 2.2.8 の挙動を模倣する）
#   verify-excluded : 検体単独の解析は verify と同じ。スコープ内解析では何も出さない
#                     （`excludePaths` が設置先を潰している状態の模倣）
#
#   ---- probe-phpstan-levels.sh 用 ----
#   levels : neon の `level:` が 10 を超えたら「level 設定ファイルが無い」と応答する。
#            それ以外は、検体ディレクトリ中の `// @probe-expect <id> <variant>` の直後の行に
#            <id> を出す。変種 `general` は verify と同じく上記設定がある場合のみ出す
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

# --configuration=<neon> の中身から、オフセット感度の必須パラメータが有効かを見る。
stub_config_path() {
  local a
  for a in "$@"; do
    case "${a}" in
      --configuration=*) printf '%s\n' "${a#--configuration=}"; return 0 ;;
    esac
  done
  return 0
}
stub_general_offset_on() {
  local cfg
  cfg="$(stub_config_path "$@")"
  [ -n "${cfg}" ] && [ -f "${cfg}" ] \
    && grep -qE '^[[:space:]]*reportPossiblyNonexistentGeneralArrayOffset:[[:space:]]*true' "${cfg}"
}
# 最後の位置引数（`--` で始まらないもの）。解析対象のパス引数を指す。
stub_last_path() {
  local a last=""
  for a in "$@"; do
    case "${a}" in
      --*|analyse) ;;
      *) last="${a}" ;;
    esac
  done
  printf '%s\n' "${last}"
}
# $1: ファイル / $2: マーカー名 / $3: 1 なら変種 general を出す
# 出力: JSON の messages 配列の要素（カンマ区切り）
stub_marker_messages() {
  local file="$1" marker="$2" general="$3" sep="" hit ln id variant
  while IFS= read -r hit; do
    [ -n "${hit}" ] || continue
    ln=$(( ${hit%%:*} + 1 ))
    id="$(printf '%s' "${hit#*:}" | sed -n "s/.*@${marker}[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p")"
    variant="$(printf '%s' "${hit#*:}" | sed -n "s/.*@${marker}[[:space:]]\{1,\}[^[:space:]]\{1,\}[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p")"
    if [ "${marker}" = "gate-require" ] || [ "${variant}" = "general" ]; then
      [ "${general}" -eq 1 ] || continue
    fi
    printf '%s{"message":"stub","line":%s,"ignorable":true,"identifier":"%s"}' "${sep}" "${ln}" "${id}"
    sep=","
  done < <(grep -nE "^[[:space:]]*// @${marker}[[:space:]]" "${file}" 2>/dev/null || true)
}

general=0
if stub_general_offset_on "$@"; then
  general=1
fi

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
  verify|verify-excluded)
    target="$(stub_last_path "$@")"
    if [ -z "${target}" ]; then
      # スコープ内解析（パス引数なし）
      if [ "${FAKE}" = "verify-excluded" ]; then
        printf '{"totals":{"errors":0,"file_errors":0},"files":{},"errors":[]}\n'
        exit 0
      fi
      target="$(find "${PHPSTAN_FAKE_PLANT_DIR:-/nonexistent}" -maxdepth 1 -name '__gate_probe_*.php' 2>/dev/null | head -1)"
      if [ -z "${target}" ]; then
        printf '{"totals":{"errors":0,"file_errors":0},"files":{},"errors":[]}\n'
        exit 0
      fi
    fi
    msgs='{"message":"stub","line":1,"ignorable":true,"identifier":"offsetAccess.nonOffsetAccessible"}'
    extra="$(stub_marker_messages "${target}" gate-require "${general}")"
    [ -z "${extra}" ] || msgs="${msgs},${extra}"
    printf '{"totals":{"errors":0,"file_errors":1},"files":{"%s":{"errors":1,"messages":[%s]}},"errors":[]}\n' \
      "${target}" "${msgs}"
    exit 1
    ;;
  levels)
    cfg="$(stub_config_path "$@")"
    lvl="$(sed -n 's/^[[:space:]]*level:[[:space:]]*\([0-9]\{1,\}\).*/\1/p' "${cfg}" 2>/dev/null | head -1)"
    [ -n "${lvl}" ] || lvl=0
    if [ "${lvl}" -gt 10 ]; then
      printf 'Level config file phar:///stub/conf/config.level%s.neon was not found.\n' "${lvl}"
      exit 1
    fi
    dir="$(stub_last_path "$@")"
    files=""
    fsep=""
    for f in "${dir}"/*.php; do
      [ -f "${f}" ] || continue
      m="$(stub_marker_messages "${f}" probe-expect "${general}")"
      [ -n "${m}" ] || continue
      files="${files}${fsep}\"${f}\":{\"errors\":1,\"messages\":[${m}]}"
      fsep=","
    done
    printf '{"totals":{"errors":0,"file_errors":1},"files":{%s},"errors":[]}\n' "${files}"
    exit 1
    ;;
  *)
    printf 'stub: 未知の PHPSTAN_FAKE です: %s\n' "${FAKE}" >&2
    exit 3
    ;;
esac
