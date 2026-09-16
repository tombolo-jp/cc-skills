#!/usr/bin/env bash
#
# 開発環境をワンコマンドで起動する上位ラッパー。
#   1. 共有 Colima VM を起動（scripts/colima-start.sh に委譲）
#   2. ddev start（web/db に加え Mailpit も同時起動）
#   3. メインサイトが実際に HTTP 応答（2xx/3xx）を返すまで待機
#   4. メインサイト / Mailpit をブラウザで開く
#
# Colima VM はホスト上の全 DDEV プロジェクトで共用する。
# 他プロジェクトが先に起動していれば VM は既に動いており、1 は素通りする（正常系）。
#
# Mailpit は ddev start に同梱される。ポートはプロジェクトごとに異なるため、
# URL は DDEV の実割当から取得する。
# 「コンテナ healthy」と「サイトが応答する」は別物なので、3 で後者を確認してから開く。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="ddev"

MAIN_URL="https://__FQDN__"
# ddev describe から取れなかったときのフォールバック。.ddev/config.yaml の設定値と同じ値を埋める。
MAILPIT_URL_FALLBACK="https://__FQDN__:__MAILPIT_HTTPS_PORT__"

COLIMA_PROBE_TIMEOUT=25   # colima status がこの秒数で返らなければスリープ復帰ハングと判断（colima #460）
HTTP_WAIT_TIMEOUT=180     # サイト応答待ちの上限秒数（初回は OPcache ウォームアップで数秒かかる）

# colima status を非ブロッキングで叩き、稼働状態を判定する。
#   0 = Running / 1 = 未起動（正常・これから start する） / 2 = ハング（タイムアウト）
# macOS に timeout(1) が無いため、バックグラウンド + kill -0 ポーリングで自前実装。
probe_colima() {
  colima status --profile "${PROFILE}" >/dev/null 2>&1 &
  local pid=$!
  local waited=0
  while kill -0 "${pid}" 2>/dev/null; do
    if [[ "${waited}" -ge "${COLIMA_PROBE_TIMEOUT}" ]]; then
      kill -TERM "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true   # ジョブを静かに刈り取り "Terminated" 通知を抑制
      return 2
    fi
    sleep 1
    waited=$((waited + 1))
  done
  if wait "${pid}"; then return 0; else return 1; fi
}

# Mailpit の実 URL を ddev describe -j から取得する。
# 取得できなければ空文字を返し、呼び出し側がフォールバック値を使う。
# jq には依存しない（Brewfile の前提を増やさないため perl で拾う）。
mailpit_url_from_ddev() {
  ddev describe -j 2>/dev/null \
    | perl -ne 'if (/"mailpit_https_url"\s*:\s*"([^"]+)"/) { print $1; exit }' 2>/dev/null || true
}

# URL が 2xx/3xx を返すまでポーリング。ログイン必須アプリ等は未認証で 3xx を返すのが正常。
wait_for_http() {
  local url="$1"
  local deadline=$((SECONDS + HTTP_WAIT_TIMEOUT))
  local code=""
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    code="$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 10 "${url}")" || code="000"
    case "${code}" in
      2??|3??)
        printf '\n[dev-up] %s → HTTP %s（応答 OK）\n' "${url}" "${code}"
        return 0
        ;;
      *)
        printf '\r[dev-up] %s を待機中… (HTTP %s)   ' "${url}" "${code}"
        ;;
    esac
    sleep 2
  done
  printf '\n[dev-up] タイムアウト: %s が %ss 以内に応答しませんでした（最終 HTTP %s）\n' \
    "${url}" "${HTTP_WAIT_TIMEOUT}" "${code}" >&2
  return 1
}

echo "[dev-up] === 開発環境を起動します ==="

# --- 1. Colima ---------------------------------------------------------------
echo "[dev-up] 共有 Colima プロファイル ${PROFILE} の状態を確認します…"
set +e
probe_colima
colima_state=$?
set -e
case "${colima_state}" in
  # 他プロジェクトが起動していれば既に Running。共有 VM ではこれが通常の状態。
  0) echo "[dev-up] Colima は既に起動中です（他プロジェクトが使用中の可能性あり）" ;;
  1) echo "[dev-up] Colima は未起動です。起動します" ;;
  2)
    echo "[dev-up] Colima が ${COLIMA_PROBE_TIMEOUT}s 以内に応答しません（スリープ復帰ハングの可能性 / colima #460）" >&2
    echo "[dev-up] 次を手動実行して復旧してください:" >&2
    echo "           ddev poweroff && colima restart --profile ${PROFILE} && docker context use colima-${PROFILE}" >&2
    echo "[dev-up] ※ この復旧手順の ddev poweroff は共有 VM 上の**全プロジェクト**を停止します。" >&2
    echo "           他プロジェクトで作業中の人がいないか確認してから実行してください。" >&2
    exit 1
    ;;
esac

# 起動と docker context 切替は既存スクリプトに委譲（初回テンプレ反映も内包）
"${REPO_ROOT}/scripts/colima-start.sh"

# --- 2. ddev start -----------------------------------------------------------
echo "[dev-up] ddev start（web / db / Mailpit）…"
cd "${REPO_ROOT}"
ddev start

# --- 3. サイト応答待ち --------------------------------------------------------
# メインサイトは必須。応答しなければここで中断する。
echo "[dev-up] ${MAIN_URL} の応答を待機します（最大 ${HTTP_WAIT_TIMEOUT}s）…"
wait_for_http "${MAIN_URL}"

# --- 4. ブラウザ起動 ----------------------------------------------------------
# Mailpit のポートはプロジェクトごとに異なるため実割当を優先する。
# 取得に失敗してもブラウザ起動までは到達させる（メール確認は必須機能ではない）。
MAILPIT_URL="$(mailpit_url_from_ddev)"
if [[ -z "${MAILPIT_URL}" ]]; then
  MAILPIT_URL="${MAILPIT_URL_FALLBACK}"
  echo "[dev-up] ddev describe から Mailpit URL を取得できませんでした。設定値から組み立てます: ${MAILPIT_URL}" >&2
fi

# メインサイトを最後に開いてアクティブタブにする
open_urls=("${MAILPIT_URL}" "${MAIN_URL}")
echo "[dev-up] ブラウザを開きます: ${open_urls[*]}"
open "${open_urls[@]}"

echo "[dev-up] === 完了 ==="
echo "[dev-up] このプロジェクトだけ閉じる: ./scripts/dev-down.sh ／ 共有 VM ごと止める: ./scripts/colima-stop.sh"
