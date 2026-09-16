#!/usr/bin/env bash
#
# DDEV + Colima 開発環境の設定一式を、テンプレートからプロジェクト固有値で生成する。
# VM はホスト共通の共有 Colima プロファイル `ddev` を全プロジェクトで共用する。
#
# 必須:
#   --php <ver>        PHP バージョン（例: 8.3）
#   --mariadb <ver>    MariaDB バージョン（例: 11.4）
#   --fqdn <host.tld>  開発 FQDN（例: myapp.local）
# 任意:
#   --target <dir>     生成先リポジトリ（既定: カレントディレクトリ）
#   --name <name>      プロジェクト名（既定: --target の basename を sanitize）
#   --mailpit-port <n> Mailpit HTTPS ポートの起点（既定: 8026。既知プロジェクトが予約済み、
#                      またはホストで待ち受け中なら +2 して繰り上げ）
#   --innodb-buffer-pool <size>  innodb_buffer_pool_size（既定: 512M）
#   --setup-doc <path> 生成する手順書のパス（--target からの相対。既定: .claude/tasks/docker/setup.md）
#   --force            既存ファイルを上書きする（既定: 既存はスキップ）
#
# 廃止: --cpu / --memory / --disk
#   共有 VM のリソースは全プロジェクト共通のため固定既定値（cpu 4 / memory 8GiB / disk 80GiB）
#   を配る。作成済み VM の変更は colima 側で行う（手順書のリソース変更手順を参照）。

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES="${SKILL_DIR}/templates"

# --- 既定値 ---
TARGET="$(pwd)"
PROJECT_NAME=""
PHP_VERSION=""
MARIADB_VERSION=""
FQDN=""
INNODB_BUFFER_POOL="512M"
MAILPIT_PORT="8026"
SETUP_DOC=".claude/tasks/docker/setup.md"
FORCE="0"

# --- 共有 VM のリソース（固定定数。フラグでは変更させない）---
# 共有プロファイルは「全プロジェクトが同じ値を指していること」が成立条件であり、
# プロジェクトごとに違う値を配れる余地そのものが方式の破綻点になる。
# 変更は生成後に .colima/ddev.yaml を編集して VM を再起動する運用とする。
COLIMA_CPU="4"
COLIMA_MEMORY="8"
COLIMA_DISK="80"

# 共有 Colima プロファイル名。固定文字列であることが共有方式の前提。
COLIMA_PROFILE="ddev"

# Mailpit ポート繰り上げの試行上限（起点からのオフセット）。無限ループを避ける。
MAILPIT_SCAN_SPAN=40

# DDEV 既定の Mailpit HTTPS ポート。mailpit_*_port を持たない既知プロジェクトは
# この番号（と 1 つ下の HTTP）を占有しているとみなす。
MAILPIT_DEFAULT_HTTPS=8026

# 冒頭のコメントブロック（2 行目以降、最初の非コメント行の手前まで）をヘルプとして出力する。
# 上限を 30 行目に置いているのは暴走防止であり、ブロックが 30 行を超えるとヘルプが途中で切れる。
# 非コメント行で打ち切るのは、ブロックの後ろに続くシェルコードがヘルプに混ざらないようにするため。
usage() {
  awk 'NR >= 2 && NR <= 30 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

# --- 引数解析 ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --php)                 PHP_VERSION="$2"; shift 2 ;;
    --mariadb)             MARIADB_VERSION="$2"; shift 2 ;;
    --fqdn)                FQDN="$2"; shift 2 ;;
    --target)              TARGET="$2"; shift 2 ;;
    --name)                PROJECT_NAME="$2"; shift 2 ;;
    --mailpit-port)        MAILPIT_PORT="$2"; shift 2 ;;
    --innodb-buffer-pool)  INNODB_BUFFER_POOL="$2"; shift 2 ;;
    --setup-doc)           SETUP_DOC="$2"; shift 2 ;;
    --force)               FORCE="1"; shift ;;
    -h|--help)             usage; exit 0 ;;
    *) echo "不明な引数: $1" >&2; usage; exit 2 ;;
  esac
done

# --- 必須チェック ---
missing=()
[[ -z "$PHP_VERSION" ]]     && missing+=("--php")
[[ -z "$MARIADB_VERSION" ]] && missing+=("--mariadb")
[[ -z "$FQDN" ]]            && missing+=("--fqdn")
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "必須引数が不足しています: ${missing[*]}" >&2
  usage; exit 2
fi

# --- Mailpit 起点ポートの検証 ---
# 特権ポート（1024 未満）は非 root で bind できず、範囲外の値は DDEV 側で無効になる。
# 下限が 1025 なのは、HTTP 側が HTTPS − 1 で派生するため。1024 を許すと HTTP が 1023 になり、
# 特権ポートを避けるという検証の目的そのものが破れる。
if [[ ! "$MAILPIT_PORT" =~ ^[0-9]+$ ]]; then
  echo "--mailpit-port は数値で指定してください: $MAILPIT_PORT" >&2
  exit 2
fi
if [[ "$MAILPIT_PORT" -lt 1025 || "$MAILPIT_PORT" -gt 65535 ]]; then
  echo "--mailpit-port は 1025〜65535 の範囲で指定してください（HTTP 側が n-1 になるため特権ポートを避ける）: $MAILPIT_PORT" >&2
  exit 2
fi

TARGET="$(cd "$TARGET" && pwd)"

# --- プロジェクト名の決定 ---
# PROJECT_NAME は sed の置換値であると同時に出力パス（.ddev/mysql/<name>.cnf など）の一部でもある。
# --name の明示指定にも同じ sanitize を通すのは、`|`（sed の区切り）や `../` を含む値が
# そのまま置換値・パスとして使われるのを防ぐため。
sanitize_name() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9-]/-/g' -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//'
}

if [[ -z "$PROJECT_NAME" ]]; then
  PROJECT_NAME="$(sanitize_name "$(basename "$TARGET")")"
else
  sanitized="$(sanitize_name "$PROJECT_NAME")"
  if [[ "$sanitized" != "$PROJECT_NAME" ]]; then
    echo "[warn] --name を DDEV が扱える形へ正規化しました: ${PROJECT_NAME} → ${sanitized}" >&2
    echo "" >&2
  fi
  PROJECT_NAME="$sanitized"
fi
if [[ -z "$PROJECT_NAME" ]]; then
  echo "プロジェクト名を決定できませんでした。--name で指定してください。" >&2
  exit 2
fi

# --- FQDN を host / tld に分解 ---
FQDN_HOST="${FQDN%%.*}"
PROJECT_TLD="${FQDN#*.}"
if [[ "$FQDN_HOST" == "$FQDN" || -z "$PROJECT_TLD" ]]; then
  echo "FQDN は host.tld 形式で指定してください（例: myapp.local）: $FQDN" >&2
  exit 2
fi

# FQDN のホストラベルがプロジェクト名と異なる場合のみ additional_fqdns を追記する。
# （DDEV の正規 URL は <name>.<tld>。FQDN がそれと違うなら明示登録が要る）
if [[ "$FQDN_HOST" != "$PROJECT_NAME" ]]; then
  NEED_ADDITIONAL_FQDNS="1"
else
  NEED_ADDITIONAL_FQDNS="0"
fi

# --- Mailpit ポートの採番 ---
# 共有 VM では全プロジェクトの Mailpit がホストのポートを占有するため、
# 既知プロジェクトが使用中のポートを避けて採番する。
#
# 収集は ~/.ddev/project_list.yaml と各プロジェクトの .ddev/config.yaml を「読む」だけで行い、
# `ddev` コマンドは呼ばない。generate.sh が外部コマンドに依存しない性質
# （DDEV 未導入のマシンでも生成できる）を壊さないため。
#
# HTTPS と HTTP の両方を出力する。片方だけを見ると、奇数刻みの起点を指定した場合に
# HTTP 側が既存の HTTPS と衝突しても繰り上げが働かない。
# mailpit_*_port を持たないプロジェクト（本スキル以前に作られたもの・DDEV 既定のまま
# 運用しているもの）は DDEV 既定の 8026/8025 を占有しているため、既定値で数える。
# 「キーが無い＝未使用」と扱うと、既存プロジェクトの大半を素通りして必ず 8026 を採ってしまう。
collect_used_mailpit_ports() {
  local list="${HOME}/.ddev/project_list.yaml"
  [[ -r "$list" ]] || return 1
  local approot cfg https http found=0
  while IFS= read -r approot; do
    [[ -n "$approot" ]] || continue
    found=1
    # 生成対象自身の現行ポートは「使用中」に数えない（再生成のたびに繰り上がってしまうため）
    [[ "$approot" == "$TARGET" ]] && continue
    cfg="${approot}/.ddev/config.yaml"
    [[ -f "$cfg" ]] || continue
    https="$(awk '/^mailpit_https_port:/ { v = $2; gsub(/[^0-9]/, "", v); if (v != "") { print v; exit } }' "$cfg")"
    http="$(awk '/^mailpit_http_port:/  { v = $2; gsub(/[^0-9]/, "", v); if (v != "") { print v; exit } }' "$cfg")"
    [[ -n "$https" ]] || https="$MAILPIT_DEFAULT_HTTPS"
    [[ -n "$http"  ]] || http=$(( https - 1 ))
    printf '%s\n%s\n' "$https" "$http"
  done < <(awk '
    match($0, /^[[:space:]]+approot:[[:space:]]*/) {
      v = substr($0, RSTART + RLENGTH)
      sub(/#.*$/, "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      gsub(/["\047]/, "", v)
      if (v != "") print v
    }' "$list")
  # 一覧はあるが approot を 1 件も取り出せなかった場合も「読めなかった」として扱う。
  # 空の収集結果を「衝突なし」と解釈すると、警告なしで起点値を採ってしまうため。
  [[ "$found" == "1" ]] || return 1
  return 0
}

# ある番号が既知プロジェクトに使われているか
mailpit_port_in_use() {
  printf '%s\n' "$used_mailpit_ports" | grep -qx "$1"
}

# ホストで実際に待ち受け中のポートか（lsof があるときだけ判定する）。
#
# project_list.yaml の走査と lsof は補完関係にある。一覧は「DDEV が知っているプロジェクト」の
# 予約を停止中でも拾えるが、DDEV 以外のアプリが占有しているポートは見えない。lsof は逆に
# 「いま待ち受けているもの」しか見えず、停止中プロジェクトの予約は拾えない。両方を見る。
#
# lsof が無い環境では判定をスキップする。generate.sh が外部コマンドに依存しない性質
# （DDEV 未導入のマシンでも生成できる）を壊さないため、存在しないことを異常としない。
port_listening() {
  command -v lsof >/dev/null 2>&1 || return 1
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

# 採番候補として使えないポート（既知プロジェクトが予約済み、またはホストが待ち受け中）
mailpit_port_unavailable() {
  mailpit_port_in_use "$1" || port_listening "$1"
}

MAILPIT_HTTPS_PORT="$MAILPIT_PORT"
MAILPIT_BUMPED="0"

set +e
used_mailpit_ports="$(collect_used_mailpit_ports)"
collect_rc=$?
set -e

if [[ "$collect_rc" -ne 0 ]]; then
  # 一覧が読めなくても採番そのものは打ち切らない。lsof による待ち受け判定だけでも
  # 「起動中のプロジェクトと同じポートを配る」事故は防げるため、片肺でも走らせる。
  used_mailpit_ports=""
  echo "[warn] DDEV の既知プロジェクト一覧（${HOME}/.ddev/project_list.yaml）を読めませんでした。" >&2
  echo "       既知プロジェクトとの照合は行わず、ホストで待ち受け中のポートのみを避けて採番します。" >&2
  echo "       停止中プロジェクトのポートは検出できないため、重複がないか手動で確認してください。" >&2
  echo "" >&2
fi

scan_limit=$(( MAILPIT_PORT + MAILPIT_SCAN_SPAN ))
while mailpit_port_unavailable "$MAILPIT_HTTPS_PORT" || mailpit_port_unavailable "$(( MAILPIT_HTTPS_PORT - 1 ))"; do
  # 一覧に無いのに待ち受けている＝ DDEV 以外のプロセスの可能性があり、原因を追いにくい。
  # 繰り上げの理由をここで明示しておく。
  if port_listening "$MAILPIT_HTTPS_PORT" || port_listening "$(( MAILPIT_HTTPS_PORT - 1 ))"; then
    echo "[info] ${MAILPIT_HTTPS_PORT}/$(( MAILPIT_HTTPS_PORT - 1 )) はホスト上で待ち受け中のため繰り上げます。" >&2
  fi
  # HTTP/HTTPS のペアで 2 ポート消費するため刻みは 2
  MAILPIT_HTTPS_PORT=$(( MAILPIT_HTTPS_PORT + 2 ))
  MAILPIT_BUMPED="1"
  if [[ "$MAILPIT_HTTPS_PORT" -gt "$scan_limit" || "$MAILPIT_HTTPS_PORT" -gt 65535 ]]; then
    echo "[warn] Mailpit の空きポートを ${MAILPIT_PORT}〜${scan_limit} の範囲で見つけられませんでした。" >&2
    echo "       起点 ${MAILPIT_PORT} をそのまま採用します。--mailpit-port で別の起点を指定してください。" >&2
    echo "" >&2
    MAILPIT_HTTPS_PORT="$MAILPIT_PORT"
    MAILPIT_BUMPED="0"
    break
  fi
done
MAILPIT_HTTP_PORT=$(( MAILPIT_HTTPS_PORT - 1 ))

echo "=== 生成設定 ==="
echo "  target            : $TARGET"
echo "  project name      : $PROJECT_NAME"
echo "  fqdn              : $FQDN  (tld: $PROJECT_TLD)"
echo "  php / mariadb     : $PHP_VERSION / $MARIADB_VERSION"
echo "  colima profile    : $COLIMA_PROFILE （ホスト共通の共有 VM）"
echo "  colima cpu/mem/disk: $COLIMA_CPU / ${COLIMA_MEMORY}GiB / ${COLIMA_DISK}GiB （固定）"
echo "  mailpit port      : ${MAILPIT_HTTPS_PORT} (https) / ${MAILPIT_HTTP_PORT} (http)$([[ "$MAILPIT_BUMPED" == "1" ]] && echo " ※起点 ${MAILPIT_PORT} から繰り上げ" || echo "")"
echo "  innodb_buffer_pool: $INNODB_BUFFER_POOL"
echo "  additional_fqdns  : $([[ "$NEED_ADDITIONAL_FQDNS" == "1" ]] && echo "yes ($FQDN)" || echo "no")"
echo "  force             : $FORCE"
echo

# --- 整合性チェック: innodb_buffer_pool の 3 プロジェクト合計が共有 VM メモリの 50% を超えていないか ---
# 単位（K/M/G）と桁を解釈して MiB に正規化。共有 VM には同時に複数プロジェクトの db が載るため、
# 1 プロジェクト分ではなく「同時起動 3 プロジェクト分の合計」で判定する。
# 単位は tr で大文字へ寄せてから判定する。awk の IGNORECASE は gawk 拡張であり、
# macOS 標準 awk では効かない（`2g` のような小文字指定が黙って解釈不能になり、
# OOM ガードが無言で無効化される）。
pool_mib="$(printf '%s' "$INNODB_BUFFER_POOL" | tr '[:lower:]' '[:upper:]' | awk '
  /^[0-9]+G$/ { gsub(/G/,""); print $0 * 1024; exit }
  /^[0-9]+M$/ { gsub(/M/,""); print $0;        exit }
  /^[0-9]+K$/ { gsub(/K/,""); printf "%d", $0/1024; exit }
  /^[0-9]+$/  { printf "%d", $0/(1024*1024);   exit }
  { print "" }
')"
mem_mib=$(( COLIMA_MEMORY * 1024 ))
if [[ -z "$pool_mib" ]]; then
  echo "[warn] --innodb-buffer-pool の書式を解釈できないため、メモリ整合チェックを行いません: ${INNODB_BUFFER_POOL}" >&2
  echo "       値はそのまま .ddev/mysql/${PROJECT_NAME}.cnf へ書き出されます。MariaDB が起動しない場合は書式を確認してください。" >&2
  echo "" >&2
elif [[ $(( pool_mib * 3 )) -gt $(( mem_mib / 2 )) ]]; then
  echo "[warn] innodb_buffer_pool_size=${INNODB_BUFFER_POOL} × 同時起動 3 プロジェクト = $(( pool_mib * 3 ))MiB は" >&2
  echo "       共有 VM メモリ ${COLIMA_MEMORY}GiB の 50%（$(( mem_mib / 2 ))MiB）を超えています。" >&2
  echo "       同時起動時に mmap で OOM になる恐れあり。--innodb-buffer-pool を減らすか、同時起動数を抑えてください。" >&2
  echo "       共有 VM のメモリを増やす場合は手順書の「共有 VM のリソースを変更する」に従ってください" >&2
  echo "       （.colima/${COLIMA_PROFILE}.yaml の編集だけでは作成済みの VM に反映されません）。" >&2
  echo "" >&2
fi


# --- additional_fqdns ブロックを stdin に適用するフィルタ ---
fqdn_block() {
  if [[ "$NEED_ADDITIONAL_FQDNS" == "1" ]]; then
    perl -pe "s{^__ADDITIONAL_FQDNS_BLOCK__\$}{additional_fqdns:\n  - ${FQDN}}"
  else
    grep -v '^__ADDITIONAL_FQDNS_BLOCK__$' || true
  fi
}

# --- テンプレートを置換して書き出す ---
render() {
  local src="$1" dst="$2"
  if [[ ! -f "$src" ]]; then echo "テンプレート欠落: $src" >&2; exit 1; fi
  if [[ -e "$dst" && "$FORCE" != "1" ]]; then
    echo "[skip ] $dst （既存。--force で上書き）"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  sed \
    -e "s|__PROJECT_NAME__|${PROJECT_NAME}|g" \
    -e "s|__PHP_VERSION__|${PHP_VERSION}|g" \
    -e "s|__MARIADB_VERSION__|${MARIADB_VERSION}|g" \
    -e "s|__FQDN__|${FQDN}|g" \
    -e "s|__PROJECT_TLD__|${PROJECT_TLD}|g" \
    -e "s|__COLIMA_CPU__|${COLIMA_CPU}|g" \
    -e "s|__COLIMA_MEMORY__|${COLIMA_MEMORY}|g" \
    -e "s|__COLIMA_DISK__|${COLIMA_DISK}|g" \
    -e "s|__INNODB_BUFFER_POOL__|${INNODB_BUFFER_POOL}|g" \
    -e "s|__MAILPIT_HTTP_PORT__|${MAILPIT_HTTP_PORT}|g" \
    -e "s|__MAILPIT_HTTPS_PORT__|${MAILPIT_HTTPS_PORT}|g" \
    "$src" | fqdn_block > "$dst"
  echo "[write] $dst"
}

# --- 生成（テンプレート → 配置先）---
# colima.yaml の宛先はプロジェクト名ではなく共有プロファイル名。全プロジェクトで同一内容になる。
render "${TEMPLATES}/Brewfile"                     "${TARGET}/Brewfile"
render "${TEMPLATES}/colima.yaml"                  "${TARGET}/.colima/${COLIMA_PROFILE}.yaml"
render "${TEMPLATES}/colima-start.sh"              "${TARGET}/scripts/colima-start.sh"
render "${TEMPLATES}/colima-stop.sh"               "${TARGET}/scripts/colima-stop.sh"
render "${TEMPLATES}/dev-up.sh"                    "${TARGET}/scripts/dev-up.sh"
render "${TEMPLATES}/dev-down.sh"                  "${TARGET}/scripts/dev-down.sh"
render "${TEMPLATES}/ddev-config.yaml"             "${TARGET}/.ddev/config.yaml"
render "${TEMPLATES}/ddev-mysql.cnf"               "${TARGET}/.ddev/mysql/${PROJECT_NAME}.cnf"
render "${TEMPLATES}/ddev-zz-import.cnf.disabled"  "${TARGET}/.ddev/mysql/zz-import.cnf.disabled"
render "${TEMPLATES}/ddev-php.ini"                 "${TARGET}/.ddev/php/${PROJECT_NAME}.ini"
render "${TEMPLATES}/setup.md"                     "${TARGET}/${SETUP_DOC}"
render "${TEMPLATES}/migrate.md"                   "${TARGET}/$(dirname "${SETUP_DOC}")/migrate.md"

# --- スクリプトに実行権限 ---
for s in colima-start.sh colima-stop.sh dev-up.sh dev-down.sh; do
  [[ -f "${TARGET}/scripts/${s}" ]] && chmod +x "${TARGET}/scripts/${s}"
done

# --- .gitignore に個人差分プロファイルを追記（重複追記しない）---
GI="${TARGET}/.gitignore"
LINE=".colima/${COLIMA_PROFILE}.local.yaml"
if [[ ! -f "$GI" ]] || ! grep -qxF "$LINE" "$GI"; then
  {
    echo ""
    echo "# Colima 個人差分用プロファイル（チーム標準は .colima/${COLIMA_PROFILE}.yaml のみコミット）"
    echo "$LINE"
  } >> "$GI"
  echo "[gitignore] $LINE を追記"
fi

echo
echo "=== 完了 ==="
echo "次の手順:"
echo "  1. 生成された手順書を確認: ${SETUP_DOC}"
echo "  2. brew bundle --file=./Brewfile && mkcert -install"
echo "  3. ./scripts/colima-start.sh && ddev start"
echo "  4. wp-config-ddev.php 生成を確認後、.ddev/config.yaml の disable_settings_management を true に切替えて ddev restart"
echo
echo "既に旧方式（プロジェクト専用 VM）で構築済みの環境がある場合は、"
echo "  $(dirname "${SETUP_DOC}")/migrate.md の移行手順に従ってください。"
