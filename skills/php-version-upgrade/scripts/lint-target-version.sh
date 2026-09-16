#!/usr/bin/env bash
# 指定PHPバージョン範囲での一括構文互換チェック
#
# 使い方:
#   lint-target-version.sh --testversion=7.4-8.3 --target-paths=path1,path2
#   lint-target-version.sh --testversion=8.3 --target-paths=wp-content/themes/mytheme
#   lint-target-version.sh --testversion=8.3 <path> [<path> ...]   # 旧形式（位置引数・当面併存）
#
# 前提: PHPCompatibility導入済みの composer 環境（phpcs + phpcompatibility/php-compatibility）
# がリポジトリのどこかに存在すること。存在しない場合は `composer require --dev` の案内を出す。
#
# 動作: 指定パス配下の *.php を対象に phpcs --standard=PHPCompatibility を実行し、
# サマリを表示する。WARNING はサマリに表示するが終了コードには含めない
# （ignore_warnings_on_exit で除外する）。
#
#   ★ **「ERROR 0件」を単独の受入基準にしてはならない。**
#     このゲートが対象バージョンの非互換を実際に検出できるかは、バージョン番号では決まらない。
#     導入している PHPCompatibility が削除 API を ERROR ではなく WARNING としか
#     報告しない場合、`ignore_warnings_on_exit` の下では**終了コードが常に 0 になる**。
#     採否は `scripts/verify-gate.sh --gate=phpcompat` の3値判定
#     （VERIFIED / DEGRADED / BLIND）で決めること。
#
# 終了コード:
#   0 : ERROR 0件（**合格ではない。verify-gate.sh で VERIFIED を得ている場合にのみ合格と読む**）
#   1 : ERROR あり
#   2 : 設定ミス・実行不能（引数不正、phpcs 未検出、phpcs 自体の実行エラー）

set -euo pipefail

TESTVERSION=""
PATHS=()
PATH_COUNT=0

# 位置パラメータはシフトしながら読む。bash 3.2（macOS標準）では空配列の "${arr[@]}" 展開が
# set -u で unbound variable になるため、要素数は専用のカウンタで管理し、
# 配列展開は要素が1つ以上あることを確認した後にだけ行う。
while [ "$#" -gt 0 ]; do
  arg="$1"
  shift
  case "${arg}" in
    --testversion=*)
      TESTVERSION="${arg#--testversion=}"
      ;;
    --target-paths=*)
      # 他のスクリプトと引数形式を揃える。値はカンマ区切り。
      _tp="${arg#--target-paths=}"
      if [ -z "${_tp}" ]; then
        echo "Error: --target-paths の値が空です。省略時の既定へは落としません。" >&2
        exit 2
      fi
      _old_ifs="${IFS}"
      IFS=','
      for _p in ${_tp}; do
        [ -n "${_p}" ] || continue
        PATHS+=("${_p}")
        PATH_COUNT=$((PATH_COUNT + 1))
      done
      IFS="${_old_ifs}"
      ;;
    -*)
      echo "Unknown option: ${arg}" >&2
      exit 2
      ;;
    *)
      # 旧形式（位置引数）。当面は受理するが、新形式を案内する。
      # 本スクリプトだけが位置引数を取る歴史的経緯は .claude/docs/scripts.md に記録している。
      echo "注意: 位置引数での指定は旧形式です。--target-paths=${arg} 形式へ移行してください。" >&2
      PATHS+=("${arg}")
      PATH_COUNT=$((PATH_COUNT + 1))
      ;;
  esac
done

if [ -z "${TESTVERSION}" ]; then
  echo "Error: --testversion=<from>-<to> または --testversion=<version> を指定してください" >&2
  echo "  例: $0 --testversion=7.4-8.3 wp-content/plugins/my-plugin" >&2
  exit 2
fi

# PHPCompatibility の testVersion 記法を検証する。
# 受け付ける形式: "8.3" / "7.4-8.3" / "7.4-"（以降すべて） / "-8.3"（以前すべて）
# 検証しないと不正な値がそのまま phpcs へ渡り、「設定ミス(2)」ではなく
# 「違反あり(1)」相当の終了コードで返って原因が分かりにくくなる。
_ver_re='[0-9]+\.[0-9]+'
_testversion_re="^(${_ver_re}|${_ver_re}-|-${_ver_re}|${_ver_re}-${_ver_re})\$"
if ! [[ "${TESTVERSION}" =~ ${_testversion_re} ]]; then
  echo "Error: --testversion の書式が不正です: ${TESTVERSION}" >&2
  echo "  指定できる形式: 8.3 / 7.4-8.3 / 7.4- / -8.3" >&2
  exit 2
fi

if [ "${PATH_COUNT}" -eq 0 ]; then
  echo "Error: 対象パスを1つ以上指定してください" >&2
  exit 2
fi

# phpcs実行バイナリを探す（リポジトリ内の複数のcomposer環境を想定）
PHPCS_BIN=""
for candidate in \
  "./vendor/bin/phpcs" \
  "./vendor/bin/phpcs.bat"
do
  if [ -x "${candidate}" ]; then
    PHPCS_BIN="${candidate}"
    break
  fi
done

if [ -z "${PHPCS_BIN}" ]; then
  found=$(find . -maxdepth 4 -path "*/vendor/bin/phpcs" -not -path "*/node_modules/*" 2>/dev/null | head -1 || true)
  if [ -n "${found}" ]; then
    PHPCS_BIN="${found}"
  fi
fi

if [ -z "${PHPCS_BIN}" ]; then
  cat >&2 <<'EOF'
Error: phpcs（PHPCompatibility）が見つかりません。
以下のいずれかの方法で導入してください（アプリ本体のcomposer.jsonとは
別の、開発ツール用composer環境への導入を推奨します）:

  composer require --dev squizlabs/php_codesniffer \
    phpcompatibility/php-compatibility \
    dealerdirect/phpcodesniffer-composer-installer

※ **どのバージョンを入れるべきかを、バージョン番号で判断しない。**
   導入後に scripts/verify-gate.sh --gate=phpcompat を実行し、
   対象バージョンの非互換を実際に検出できるか（VERIFIED / DEGRADED / BLIND）で決めること。
   バージョン番号で「このリリースなら大丈夫」と書くと、次のリリースで黙って弱いゲートになる。
EOF
  exit 2
fi

echo "Using: ${PHPCS_BIN}"
echo "Test version: ${TESTVERSION}"
echo "Target paths: ${PATHS[*]}"
echo ""

# set -e 下では非0終了で即座にスクリプトが終了してしまうため、
# 終了コードは `|| exit_code=$?` で明示的に捕捉する。
exit_code=0
"${PHPCS_BIN}" \
  --standard=PHPCompatibility \
  --runtime-set testVersion "${TESTVERSION}" \
  --runtime-set ignore_warnings_on_exit 1 \
  --extensions=php \
  --report=summary \
  "${PATHS[@]}" || exit_code=$?

case "${exit_code}" in
  0)
    echo ""
    echo "ERROR 0件（testVersion=${TESTVERSION}）"
    echo "※ これは合格ではない。scripts/verify-gate.sh --gate=phpcompat で VERIFIED を"
    echo "   得ている場合にのみ PASS と読むこと。未検証なら SKIPPED (unverified) と表記する。"
    ;;
  1)
    echo ""
    echo "NG: ERROR が検出されました。詳細は下記コマンドで確認してください:" >&2
    echo "  ${PHPCS_BIN} --standard=PHPCompatibility --runtime-set testVersion ${TESTVERSION} -p ${PATHS[*]}" >&2
    ;;
  *)
    echo ""
    # 日本語メッセージ中で変数を展開するときは必ず ${...} で囲む。
    # bash 3.2 は `$exit_code）` のように直後へ全角文字が続くと、
    # そのバイト列を変数名の一部として取り込み unbound variable になる。
    echo "Error: phpcs の実行に失敗しました（exit code: ${exit_code}）" >&2
    echo "  phpcs 自体の設定・インストール状態を確認してください。" >&2
    exit 2
    ;;
esac

exit "${exit_code}"
