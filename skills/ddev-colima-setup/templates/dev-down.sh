#!/usr/bin/env bash
#
# 当該プロジェクトの開発環境を停止する（日常の「閉じる」操作）。
#   1. ddev stop … このプロジェクトの web/db/Mailpit コンテナのみ停止
#
# ★★★ 停止の範囲 ★★★
# Colima VM はホスト上の全 DDEV プロジェクトで共用しているため、ここでは止めない。
# 他プロジェクトを巻き込まずにこのプロジェクトだけを閉じるのが本スクリプトの役割。
# マシンごと落とす（VM を止めて RAM/CPU を解放する）場合は ./scripts/colima-stop.sh を使う。
#
# 非破壊操作のみを使う。停止後の状態は永続化され、次回 `./scripts/dev-up.sh` で復帰する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[dev-down] === このプロジェクトの開発環境を停止します ==="
cd "${REPO_ROOT}"

# --- 1. ddev コンテナ停止 -----------------------------------------------------
# poweroff ではなく stop。poweroff は全プロジェクト + ルータを落とすため、
# 共有 VM 環境では他プロジェクトの作業を中断させてしまう。
echo "[dev-down] ddev stop（このプロジェクトのコンテナのみ）…"
# 失敗を握り潰さず、かつ set -e で無言終了もしない。
# VM には触れていないため escalate 先は無く、利用者に状態を伝えて終わるのが正しい。
if ! ddev stop; then
  echo "[dev-down] ddev stop が失敗しました。共有 VM と他プロジェクトには触れていません" >&2
  echo "[dev-down] docker が未到達の可能性があります。ddev list で状態を確認してください" >&2
  exit 1
fi
echo "[dev-down] このプロジェクトのコンテナを停止しました"

echo "[dev-down] === 完了（次回起動: ./scripts/dev-up.sh）==="
echo "[dev-down] 共有 VM ごと停止する場合は ./scripts/colima-stop.sh（全プロジェクトが停止します）"
