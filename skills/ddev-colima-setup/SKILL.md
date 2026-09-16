---
name: ddev-colima-setup
description: "macOS (Apple Silicon) 向けに DDEV + Colima のローカル開発環境（WordPress / クリーン HTTPS URL / MariaDB チューニング）を構築する。PHP・MariaDB バージョンと FQDN を指定すると、Colima プロファイル・DDEV 設定・起動/停止スクリプト・Brewfile・セットアップ手順書を一式生成する。トリガー: DDEV, Colima, ローカル開発環境構築, dev environment setup, ddev start, colima。"
argument-hint: "--php <ver> --mariadb <ver> --fqdn <host.local> [--mailpit-port 8026 --innodb-buffer-pool 512M --name NAME]"
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# DDEV + Colima 開発環境セットアップ

macOS（Apple Silicon）向けに、DDEV + Colima による WordPress ローカル開発環境を構築する。
ポート番号なしのクリーン HTTPS URL（`https://<fqdn>`）、標準規模 WordPress 向けの MariaDB
チューニング、ワンコマンド起動/停止スクリプトを含む構成を、**3 つの入力値だけで**一式生成する。

VM はホスト共通の**共有 Colima プロファイル `ddev`** を全プロジェクトで共用する。macOS の 443 は
1 つしかなく、それを占有する DDEV ルータも 1 Docker ホストに 1 つのため、クリーン HTTPS URL を
複数プロジェクトで同時に成立させるにはこの方式しかない。

このディレクトリの `templates/` には固有名詞を一切含まないテンプレートが置かれており、
`scripts/generate.sh` がプレースホルダを実値に置換して対象リポジトリへ配置する。

## 入力

| 必須 | 内容 | 例 |
|---|---|---|
| `--php` | PHP バージョン | `8.3` |
| `--mariadb` | MariaDB バージョン | `11.4` |
| `--fqdn` | 開発 FQDN（`host.tld` 形式） | `myapp.local` |

| 任意 | 内容 | 既定 |
|---|---|---|
| `--name` | DDEV プロジェクト名 | 対象ディレクトリ名を sanitize した値 |
| `--mailpit-port` | Mailpit HTTPS ポートの起点（HTTP は `n-1`） | `8026`（既知プロジェクトが予約済み、またはホストで待ち受け中なら +2 して繰り上げ） |
| `--innodb-buffer-pool` | `innodb_buffer_pool_size` | `512M` |
| `--target` | 生成先リポジトリ | カレントディレクトリ |
| `--setup-doc` | 手順書の出力パス（target からの相対） | `.claude/tasks/docker/setup.md` |
| `--force` | 既存ファイルを上書き | （既定はスキップ） |

**廃止**: `--cpu` / `--memory` / `--disk` は受け付けない（指定すると exit 2）。共有 VM の
リソースは全プロジェクト共通のため固定値（cpu `4` / memory `8` GiB / disk `80` GiB）を配る。
作成済み VM の値を変えるには colima 側へ渡す必要がある（`colima start --profile ddev --cpu N --memory N`）。
`.colima/ddev.yaml` の編集だけでは反映されない — このファイルは初回作成時の元と、差異警告の期待値である。
手順は生成される手順書の「共有 VM のリソースを変更する」にある。

`--name` 未指定時はカレント（または `--target`）ディレクトリ名から自動導出する
（小文字化し `[^a-z0-9-]` をハイフンに置換）。FQDN のホストラベルが
プロジェクト名と異なる場合は `.ddev/config.yaml` に `additional_fqdns` を自動追記する。
Mailpit ポートは `~/.ddev/project_list.yaml` から既知プロジェクトの使用中ポートを収集し、
衝突すれば 2 刻みで繰り上げる（読めない場合は起点値を採用して警告）。

## 手順

1. **入力値を確定する。** 引数から `--php` / `--mariadb` / `--fqdn` を取得する。
   いずれかが欠けていれば `AskUserQuestion` で確認する（任意項目は既定値のままでよい）。

2. **生成スクリプトを実行する。** 対象リポジトリ（既定: カレント）に対して:
   ```bash
   bash <skill-dir>/scripts/generate.sh --php <ver> --mariadb <ver> --fqdn <host.local>
   ```
   生成物: `Brewfile` / `.colima/ddev.yaml` /
   `scripts/{colima-start,colima-stop,dev-up,dev-down}.sh` /
   `.ddev/config.yaml` / `.ddev/mysql/<name>.cnf` / `.ddev/mysql/zz-import.cnf.disabled` /
   `.ddev/php/<name>.ini` / 手順書（既定 `.claude/tasks/docker/setup.md`）/
   移行手順書（手順書と同じディレクトリの `migrate.md`）。

3. **生成結果を報告する。** 書き出されたファイル一覧、採番された Mailpit ポート、
   `disable_settings_management` を初回起動後に `true` へ切り替える必要がある旨を伝える。
   旧方式（プロジェクト専用 VM）で構築済みの環境がある場合は `migrate.md` を案内する。

4. **任意: 実際の構築を提案する。** ユーザーが希望すれば以下を案内/実行する。
   いずれも sudo 入力・長時間処理・対話を伴う点を明示すること:
   ```bash
   brew bundle --file=./Brewfile
   mkcert -install                      # sudo
   ./scripts/colima-start.sh            # 初回 VM 作成は 5〜10 分
   ddev start                           # /etc/hosts 登録で sudo
   # wp-config-ddev.php 生成と wp-config.php への require 行を確認後:
   #   .ddev/config.yaml の disable_settings_management を true に変更し
   ddev restart
   ./scripts/dev-up.sh
   ```
   停止は 2 段ある。`./scripts/dev-down.sh` は当該プロジェクトのみ、
   `./scripts/colima-stop.sh` は共有 VM ごと（= 全プロジェクト）を停止する。

5. **手順書を案内する。** 生成した手順書（既定 `.claude/tasks/docker/setup.md`）が、
   新規メンバー向けの再現手順・DB 投入（任意）・トラブルシュートを含むことを伝える。

6. **複数プロジェクトを続けて作る場合は、1 つずつ `ddev start` まで済ませてから次を生成する。**
   Mailpit ポートの採番は `~/.ddev/project_list.yaml` と、ホストで待ち受け中のポートを見る。
   **プロジェクトが一覧に載るのは `ddev start` した時点**であり、生成しただけのものは
   次の採番から見えない。2 つ続けて生成すると両方が同じポート（既定 8026）を持ち、
   2 つ目の `ddev start` がポート衝突で失敗する。
   ユーザーがまだ `ddev start` しない場合は、2 つ目以降に `--mailpit-port` を明示指定する
   （例: 1 つ目が 8026 なら 2 つ目は `--mailpit-port 8028`）。

## 設計メモ

- **`disable_settings_management` は `false` で生成する。** 初回 `ddev start` で
  `wp-config-ddev.php` を生成させ、require 行が入ったのを確認してから `true` に切替える。
  最初から `true` にすると DB 接続設定が作られず WordPress が DB に繋がらない。
- **不可変な VM 項目**（`vmType: vz` / `mountType: virtiofs` / `arch: aarch64`）は固定。
  これらは Colima VM 作成後に変更できず、変更すると VM 再作成（= DB データ消失）になる。
  共有 VM ではこの消失が**全プロジェクトに及ぶ**。
- **共有プロファイル名 `ddev` は固定文字列。** フラグにもプレースホルダにもしない。
  可変にすると 1 つ目と 2 つ目で別 VM が作られた時点で共有方式が壊れるため。
- **停止の粒度を 2 つに分けている。** `dev-down.sh` は `ddev stop`（当該プロジェクト）、
  `colima-stop.sh` は `ddev poweroff` + `colima stop`（全プロジェクト + VM）。
- **Mailpit はプロジェクトごとに別ポート。** ルータの 80/443 は Host ヘッダで振り分けられるが、
  Mailpit はホストのポートを直接占有するため衝突する。
- **DB 投入は任意。** 既存ダンプがあれば手順書 §4 で投入、無ければ空 DB で開始できる。
- **暗号鍵などの秘密値**を扱うプロジェクトでは `wp-config.php` を git 管理外に保ち、
  安全な経路で受け渡す（手順書 §3 に注意書きあり）。

## 補足: Skill の有効化

このスキルは `cc-skills` プラグインに含まれる。プラグインとして導入していれば
（クラウドセッションを含め）`/ddev-colima-setup` でそのまま呼び出せる。
プラグインを使わない場合は、このディレクトリを `~/.claude/skills/` または対象
リポジトリの `.claude/skills/` へシンボリックリンク / コピーする。直接呼ばない
場合でも `scripts/generate.sh` を単体実行すれば生成は可能。

`<SKILL>` = このスキル自身のディレクトリ。プラグイン導入時は
`${CLAUDE_PLUGIN_ROOT}/skills/ddev-colima-setup/`、コピー導入時は
`~/.claude/skills/ddev-colima-setup/`。

> **実行環境の前提**: このスキルは macOS（Apple Silicon）のローカル環境を構築する。
> Claude Code のクラウドセッションには Colima / DDEV も macOS も無いため、
> **生成された設定一式をリポジトリへコミットするところまで**がクラウドでできる範囲で、
> `colima start` / `ddev start` の実行は手元の macOS で行う。
