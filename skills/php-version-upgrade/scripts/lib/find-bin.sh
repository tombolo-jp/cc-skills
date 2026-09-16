#!/usr/bin/env bash
# 外部ツールのバイナリ探索（共有関数ライブラリ）
#
# 使い方:
#   source "$(dirname "$0")/lib/find-bin.sh"
#   PHPSTAN_BIN="$(find_bin_require phpstan)" || exit 2
#
# 前提: 単体実行するスクリプトではない。`source` して使う。
#   実行ビットを付けない（0644）。呼び出し側の `set -euo pipefail` を前提とする。
#
# 動作と終了コード:
#   このファイルは関数定義のみで、それ自体は終了コードを返さない。
#   `find_bin_require` は探索に失敗すると導入方法を stderr へ案内して 2 を返す
#   （呼び出し側が `|| exit 2` で受けること）。
#
# 存在理由: phpcs / phpstan / jq の探索ロジックが複数スクリプトへ重複すると必ずズレる。
#   探索の定義はこのファイル1箇所に置く。

# バイナリを探す。見つかればパスを stdout へ出して 0、無ければ 1。
# $1: 実行ファイル名 / $2: 探索順（`vendor` なら vendor/bin を PATH より優先）
find_bin_search() {
  local name="$1"
  local prefer="${2:-vendor}"
  local candidate
  local found

  if [ "${prefer}" = "vendor" ]; then
    for candidate in "./vendor/bin/${name}" "./vendor/bin/${name}.bat"; do
      if [ -x "${candidate}" ]; then
        printf '%s\n' "${candidate}"
        return 0
      fi
    done
  fi

  if command -v "${name}" >/dev/null 2>&1; then
    command -v "${name}"
    return 0
  fi

  # リポジトリ内に複数の composer 環境がある場合のフォールバック。
  # -maxdepth 4 は「開発ツール用 composer 環境をサブディレクトリへ置く」構成を想定した深さ。
  found=$(find . -maxdepth 4 -path "*/vendor/bin/${name}" -not -path "*/node_modules/*" 2>/dev/null | head -1 || true)
  if [ -n "${found}" ]; then
    printf '%s\n' "${found}"
    return 0
  fi

  return 1
}

# 見つからない場合に導入方法を案内する。
# **ツール名ごとに案内を変える。** 「見つかりません」だけでは次の行動が決まらない。
find_bin_hint() {
  local name="$1"
  case "${name}" in
    phpstan)
      cat >&2 <<'EOF'
Error: phpstan が見つかりません。
以下で導入してください（アプリ本体の composer.json とは別の、
開発ツール用 composer 環境への導入を推奨します）:

  composer require --dev phpstan/phpstan
EOF
      ;;
    phpcs)
      cat >&2 <<'EOF'
Error: phpcs（PHPCompatibility）が見つかりません。
以下で導入してください:

  composer require --dev squizlabs/php_codesniffer \
    phpcompatibility/php-compatibility \
    dealerdirect/phpcodesniffer-composer-installer

※ 導入後、そのバージョンが対象 PHP バージョンを実際に検出できるかは
   scripts/verify-gate.sh --gate=phpcompat で必ず確認すること。
   バージョン番号で可否を判断しない（検出できるかどうかが唯一の基準）。
EOF
      ;;
    jq)
      cat >&2 <<'EOF'
Error: jq が見つかりません。
以下のいずれかで導入してください:

  macOS:        brew install jq
  Debian/Ubuntu: apt-get install jq
  RHEL/CentOS:  yum install jq
EOF
      ;;
    *)
      printf 'Error: %s が見つかりません。\n' "${name}" >&2
      ;;
  esac
}

# 探索し、見つからなければ案内して 2 を返す。
# 呼び出し側は `BIN="$(find_bin_require phpstan)" || exit 2` の形で受ける。
find_bin_require() {
  local name="$1"
  local prefer="${2:-vendor}"
  local bin

  if bin=$(find_bin_search "${name}" "${prefer}"); then
    printf '%s\n' "${bin}"
    return 0
  fi

  find_bin_hint "${name}"
  return 2
}
