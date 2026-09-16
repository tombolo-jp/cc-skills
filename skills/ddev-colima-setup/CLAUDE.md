# CLAUDE.md — ddev-colima-setup

## プロジェクト概要

macOS（Apple Silicon）向けに DDEV + Colima の WordPress ローカル開発環境を構築する
**Claude Code スキル**。アプリケーションではない。

`templates/` に固有名詞を含まないテンプレート一式を置き、`scripts/generate.sh` が
`__PLACEHOLDER__` を実値へ置換して対象リポジトリへ配置する。必須入力は
PHP バージョン / MariaDB バージョン / FQDN の 3 つ。

VM はホスト共通の**共有 Colima プロファイル `ddev`**（固定文字列）を全プロジェクトで共用する。
リソースはフラグではなく `generate.sh` 内の固定定数（cpu 4 / memory 8GiB / disk 80GiB）。
停止は 2 段: `dev-down.sh` は当該プロジェクトのみ、`colima-stop.sh` は全プロジェクト＋VM。

生成物: `Brewfile` / `.colima/ddev.yaml` /
`scripts/{colima-start,colima-stop,dev-up,dev-down}.sh` /
`.ddev/config.yaml` / `.ddev/mysql/<name>.cnf` / `.ddev/mysql/zz-import.cnf.disabled` /
`.ddev/php/<name>.ini` / 手順書（既定 `.claude/tasks/docker/setup.md`）/
移行手順書（手順書と同じディレクトリの `migrate.md`）。

## 開発コマンド

ビルド・テスト・依存管理の仕組みは無い。検証は生成の実行で行う。

```bash
# 構文チェック
bash -n scripts/generate.sh

# スクラッチディレクトリへ生成して確認
d=$(mktemp -d)
bash scripts/generate.sh --php 8.3 --mariadb 11.4 --fqdn myapp.local --target "$d"
grep -rn '__[A-Z_]*__' "$d" | grep -v '__DIR__'   # 何も出なければ置換漏れ無し
# （__DIR__ は setup.md の wp-config.php サンプル内の PHP マジック定数。除外対象）

# ヘルプ（generate.sh の 2〜30 行目のコメントを出力する）
bash scripts/generate.sh --help
```

FQDN のホストラベルが対象ディレクトリ名と一致するケースでも一度生成し、
`__ADDITIONAL_FQDNS_BLOCK__` の削除分岐を確認すること。廃止フラグの拒否も確認する:

```bash
bash scripts/generate.sh --php 8.3 --mariadb 11.4 --fqdn myapp.local --cpu 8 ; echo "exit=$?"  # exit=2
```

## アーキテクチャ概要

```
引数 ──▶ scripts/generate.sh
           必須チェック → --mailpit-port 検証 → PROJECT_NAME 導出 → FQDN 分解
           → Mailpit ポート採番（~/.ddev/project_list.yaml ＋ lsof の LISTEN 判定。ddev は呼ばない）
           → innodb_buffer_pool × 3 と共有 VM memory の整合警告
           → render(): sed（11 プレースホルダ）+ fqdn_block() → $TARGET
           → chmod +x（4 本）/ .gitignore 追記
```

- プレースホルダ追加は **テンプレートと `render()` の `sed` の 2 箇所編集**。片方だけだと
  そのままユーザーのリポジトリへ出力される。
- `__ADDITIONAL_FQDNS_BLOCK__` のみ行単位で `fqdn_block()` が処理する（`sed` 対象外）。
  行頭・単独行であることが前提。
- `render()` は既存ファイルをスキップする（`--force` で上書き）。実プロジェクトに対して
  実行されるため、この非破壊既定は維持する。
- 共有プロファイル名 `ddev` は `generate.sh` の `COLIMA_PROFILE` と、
  `colima-start.sh` / `colima-stop.sh` / `dev-up.sh` の `PROFILE` に分散している。
  変更するなら 4 箇所を同時に直す（可変にしてはならない。共有方式が壊れる）。
- `templates/setup.md` は生成先で利用者が読む手順書。他テンプレートの挙動を変えたら
  必ず追随させる。`templates/migrate.md` は旧方式からの一度きりの移行手順書。

## Claude Code Reference Docs

Detailed technical reference documents in `.claude/docs/`.
Rules for reading/updating these docs are in `.claude/rules/`.

`.claude/docs/runtime-contracts.md` は、実際の障害から得られた順序制約と不可逆操作
（`disable_settings_management` の切替順、Colima の変更不可項目、`zz-import.cnf` の
戻し忘れ、`xhgui` によるディスク枯渇、共有 VM における障害の全プロジェクトへの波及、
Mailpit ポートの衝突など）を記録している。チューニング値や既定値を変更する前に必ず読むこと。
メモリ予算は「1 プロジェクト分」ではなく「同時 3 プロジェクト分の積み上げ」で決まる。
