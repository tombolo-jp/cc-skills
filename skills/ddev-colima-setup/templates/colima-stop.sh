#!/usr/bin/env bash
#
# 共有 Colima VM を停止する（就業終了・ホスト再起動前などマシンごと落とすとき）。
#   1. ddev poweroff … 全 ddev プロジェクト + Traefik ルータを停止
#   2. colima stop   … 共有 VM 自体を停止し RAM/CPU を解放
#
# ★★★ 影響範囲 ★★★
# この VM はホスト上の全 DDEV プロジェクトで共用している。
# したがって本スクリプトは「今いるプロジェクト」ではなく、
# **起動中の全プロジェクトを停止する**。
# 当該プロジェクトだけを閉じたい場合は ./scripts/dev-down.sh を使うこと。
#
# 順序が重要: コンテナ(VM 内)を先に落としてから VM を止める。
# 非破壊操作のみを使う。colima の VM 削除サブコマンドは named volume(DB データ)を
# 全プロジェクト分まとめて破壊するため、ここでは絶対に使わない（このスクリプトが
# 呼ぶのは stop だけであり、削除系は migrate.md の移行手順にしか置かない）。
# 停止後の状態は永続化され、次回 `./scripts/dev-up.sh` で元の状態に復帰する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="ddev"

COLIMA_PROBE_TIMEOUT=25   # colima status がこの秒数で返らなければハングと判断（colima #460）

# colima status を非ブロッキングで叩き、稼働状態を判定する。
#   0 = Running / 1 = 停止済み（何もしない） / 2 = ハング（タイムアウト）
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

echo "[colima-stop] === 共有 VM を停止します（全プロジェクトが停止します）==="
cd "${REPO_ROOT}"

# --- 1. ddev コンテナ停止 -----------------------------------------------------
# poweroff は全 ddev プロジェクト + ルータを停止する。
# VM が既にハング/停止していて docker 未到達でも、VM 停止まで進めるよう失敗を許容。
echo "[colima-stop] ddev poweroff（全プロジェクト + ルータ）…"
if ddev poweroff; then
  echo "[colima-stop] 全 ddev コンテナを停止しました"
else
  echo "[colima-stop] ddev poweroff が非正常終了（docker 未到達の可能性）。VM 停止に進みます" >&2
fi

# --- 2. 共有 Colima VM 停止 ---------------------------------------------------
echo "[colima-stop] 共有プロファイル ${PROFILE} の状態を確認します…"
set +e
probe_colima
colima_state=$?
set -e
case "${colima_state}" in
  0)
    echo "[colima-stop] 共有 VM を停止します…"
    colima stop --profile "${PROFILE}"
    ;;
  1)
    echo "[colima-stop] 共有 VM は既に停止済みです"
    ;;
  2)
    echo "[colima-stop] Colima が ${COLIMA_PROBE_TIMEOUT}s 以内に応答しません。--force で強制停止します" >&2
    colima stop --force --profile "${PROFILE}"
    ;;
esac

echo "[colima-stop] === 完了（次回起動: ./scripts/dev-up.sh）==="
