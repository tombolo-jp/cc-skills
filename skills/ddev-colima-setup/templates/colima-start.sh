#!/usr/bin/env bash
#
# ホスト共通の共有 Colima プロファイルを起動する。
#
# この VM は全 DDEV プロジェクトで共用する 1 台であり、プロファイル名は固定値 `ddev`。
# 名前を可変にすると、1 つ目と 2 つ目で別 VM が作られた時点で共有方式が壊れるため、
# フラグにもプレースホルダにもしない。
#
# - 初回（VM が無い）: .colima/ddev.yaml から値を抽出し、
#                       明示的な CLI フラグで `colima start` を呼ぶ。
#                       これは colima v0.10 系が ~/.colima/<profile>/colima.yaml を
#                       初回起動時に読まず CLI 既定値（cpu:2/mem:2GiB）で作ってしまうため。
# - 2 回目以降:        既存設定で `colima start --profile ddev` を実行（速い）
#                       このとき既存 VM の実リソースとテンプレ期待値の差異を警告する。
#                       VM は勝手に作り直さない（全プロジェクトの DB データが消えるため）。
# - 最後に docker context を colima-ddev に切替
#
# 他のプロジェクトが既にこの VM を起動していれば、ここは「起動済み」で素通りする。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="ddev"
TEMPLATE="${REPO_ROOT}/.colima/${PROFILE}.yaml"
INSTANCE_DIR="${HOME}/.colima/_lima/colima-${PROFILE}"

if [[ ! -f "${TEMPLATE}" ]]; then
  echo "[colima-start] テンプレートが見つかりません: ${TEMPLATE}" >&2
  exit 1
fi

# テンプレ yaml から最上位スカラー値を抜き出す（yq 非依存）。
# - コメント末尾を除去
# - クオート（'/"）を剥がす
# - インデント付きのネスト値は拾わない（最上位のみ）
yaml_get() {
  local key="$1"
  awk -v k="^${key}:" '
    $0 ~ k && match($0, /:[[:space:]]*/) {
      v = substr($0, RSTART + RLENGTH)
      sub(/#.*$/, "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      gsub(/^"(.*)"$/, "\\1", v); gsub(/^'\''(.*)'\''$/, "\\1", v)
      print v
      exit
    }
  ' "${TEMPLATE}"
}

# `colima list --json` の当該プロファイル行から数値フィールドを取り出す。
# 取り出せない場合は空文字を返す（呼び出し側が差異警告をスキップする）。
json_num() {
  local key="$1"
  KEY="${key}" perl -ne 'if (/"$ENV{KEY}"\s*:\s*(\d+)/) { print $1; exit }'
}

# 既存 VM の実リソースとテンプレ期待値を比較し、食い違いを stderr へ警告する。
#
# 2 つ目以降のプロジェクトで .colima/ddev.yaml を書き換えても VM には反映されない。
# 無言の不一致は「設定したつもり」を生むため、ここで可視化する。
# 警告は非致命であり、取得も解釈もできなければ黙ってスキップする
# （警告機能の不調が起動そのものを妨げてはならない）。
warn_resource_drift() {
  local line cpus mem_bytes disk_bytes mem_gib disk_gib
  local want_cpu want_mem want_disk
  local drift=()

  line="$(colima list --json 2>/dev/null | perl -ne 'print if /"name"\s*:\s*"'"${PROFILE}"'"/' 2>/dev/null)"
  [[ -n "${line}" ]] || return 0

  cpus="$(printf '%s' "${line}" | json_num cpus)"
  mem_bytes="$(printf '%s' "${line}" | json_num memory)"
  disk_bytes="$(printf '%s' "${line}" | json_num disk)"
  [[ -n "${cpus}" && -n "${mem_bytes}" && -n "${disk_bytes}" ]] || return 0

  mem_gib=$(( mem_bytes / 1024 / 1024 / 1024 ))
  disk_gib=$(( disk_bytes / 1024 / 1024 / 1024 ))

  want_cpu="$(yaml_get cpu)"
  want_mem="$(yaml_get memory)"
  want_disk="$(yaml_get disk)"

  [[ -n "${want_cpu}"  && "${cpus}"     != "${want_cpu}"  ]] && drift+=("cpu: 実 ${cpus} / 期待 ${want_cpu}")
  [[ -n "${want_mem}"  && "${mem_gib}"  != "${want_mem}"  ]] && drift+=("memory: 実 ${mem_gib}GiB / 期待 ${want_mem}GiB")
  [[ -n "${want_disk}" && "${disk_gib}" != "${want_disk}" ]] && drift+=("disk: 実 ${disk_gib}GiB / 期待 ${want_disk}GiB")

  if [[ ${#drift[@]} -gt 0 ]]; then
    echo "[colima-start] 既存の共有 VM のリソースが ${TEMPLATE} の期待値と異なります:" >&2
    local d
    for d in "${drift[@]}"; do
      echo "                 - ${d}" >&2
    done
    echo "               VM は作り直しません（全プロジェクトの DB データが消えるため）。" >&2
    echo "               本ファイルの編集だけでは VM に反映されません（colima は自身の保存済み設定を読むため）。" >&2
    echo "               揃える手順は手順書の「共有 VM のリソースを変更する」を参照してください。" >&2
  fi
  return 0
}

if [[ ! -d "${INSTANCE_DIR}" ]]; then
  echo "[colima-start] 初回起動: テンプレートから CLI フラグを組み立てて共有 VM を作成します"

  CPU="$(yaml_get cpu)"
  MEM="$(yaml_get memory)"
  DISK="$(yaml_get disk)"
  ARCH="$(yaml_get arch)"
  VM_TYPE="$(yaml_get vmType)"
  MOUNT_TYPE="$(yaml_get mountType)"
  CPU_TYPE="$(yaml_get cpuType)"

  missing=()
  [[ -z "${CPU}"        ]] && missing+=("cpu")
  [[ -z "${MEM}"        ]] && missing+=("memory")
  [[ -z "${DISK}"       ]] && missing+=("disk")
  [[ -z "${ARCH}"       ]] && missing+=("arch")
  [[ -z "${VM_TYPE}"    ]] && missing+=("vmType")
  [[ -z "${MOUNT_TYPE}" ]] && missing+=("mountType")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[colima-start] テンプレ ${TEMPLATE} から値を取得できませんでした: ${missing[*]}" >&2
    exit 1
  fi

  args=(
    --profile "${PROFILE}"
    --cpus "${CPU}"
    --memory "${MEM}"
    --disk "${DISK}"
    --arch "${ARCH}"
    --vm-type "${VM_TYPE}"
    --mount-type "${MOUNT_TYPE}"
  )
  [[ -n "${CPU_TYPE}" ]] && args+=(--cpu-type "${CPU_TYPE}")

  colima start "${args[@]}"
else
  # 稼働判定は colima status の終了コード（0=稼働 / 非ゼロ=停止）で行う。
  # 出力文字列で判定してはならない: colima status のメッセージは小文字の
  # "is running" / "is not running" であり、大文字の "Running" は colima list の
  # STATUS 列にしか現れない。文字列 grep では「起動済みなら素通り」の分岐が決して成立せず、
  # 他プロジェクトが使用中の VM に対して毎回 colima start を投げることになる。
  set +e
  colima status --profile "${PROFILE}" >/dev/null 2>&1
  status_rc=$?
  set -e
  if [[ "${status_rc}" -eq 0 ]]; then
    echo "[colima-start] 共有プロファイル ${PROFILE} は既に起動中（他プロジェクトが使用中の可能性あり）"
  else
    echo "[colima-start] 既存の共有 VM を再起動します"
    colima start --profile "${PROFILE}"
  fi

  # 差異警告は情報提供のみ。失敗しても起動を妨げない。
  set +e
  warn_resource_drift
  set -e
fi

docker context use "colima-${PROFILE}"
echo "[colima-start] 完了。次に: ddev start"
