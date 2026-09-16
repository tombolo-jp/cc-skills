# CLAUDE.md

## プロジェクト概要

**`php-version-upgrade`** — WordPress の PHP バージョンアップを体系的に検証・修正する [Claude Code](https://claude.com/claude-code) スキル。

このディレクトリは**アプリケーションではなくスキルそのもの**である。配布物は Markdown（手順書＋リファレンス）と bash スクリプト1本。
`cc-skills` プラグインの `skills/php-version-upgrade/` として配布され、プラグイン導入時は
`${CLAUDE_PLUGIN_ROOT}/skills/php-version-upgrade/`、個人スキルとしてコピーした場合は
`~/.claude/skills/php-version-upgrade/` がスキルディレクトリになる。

スキルの目的は、Rector 等による機械置換の **①修正漏れ**（未定義キー/変数、null 引数、依存パッケージの API 破壊等）と
**②過剰変換**（`LevelSetList` による旧バージョン非互換構文へのアップグレード）の両方を、
「静的解析 → 人手レビュー → 実データ実行」の3層で潰すこと。

ライセンス: GPLv3

## 構成

```
php-version-upgrade/
├── SKILL.md                          # 手順本体（frontmatter + フェーズ0〜5）※実行エントリポイント
├── README.md                         # 人間向け紹介（SKILL.md のミラー）
├── references/
│   ├── breaking-changes.md           # PHP破壊的変更カタログ §1〜§6 ＋ P1〜P8 早見表
│   ├── rector-config.md              # Rector 推奨設定と「やりすぎ」回避
│   └── wordpress-notes.md            # WordPress 固有の注意点（polyfill / stubs 等）
└── scripts/
    └── lint-target-version.sh        # PHPCompatibility ラッパー（ERROR 0件ゲート）
```

## 開発コマンド

**ビルド・テスト・CI・パッケージマネージャは無い。** 検証手段は以下のみ。

```bash
bash -n scripts/lint-target-version.sh      # シェルスクリプト構文チェック
shellcheck scripts/lint-target-version.sh   # 静的解析（デフォルト severity で0件を維持）
grep -n '§' SKILL.md references/*.md        # セクション番号の参照元を洗い出す
grep -n 'フェーズ' references/*.md           # フェーズ番号の逆参照を洗い出す
```

シェルスクリプトの終了コード分岐を変更した場合は、`bash -n` と shellcheck だけでは不十分。
phpcs をスタブに差し替えて全分岐を実行して確認する（手順は `.claude/docs/scripts.md`「検証」）。

## アーキテクチャ要約

### progressive disclosure

`SKILL.md`（常時ロード：手順・分岐・判断基準）→ `references/*.md`（必要時のみ：カタログ・設定例）→ `scripts/*`（実行）。
SKILL.md には「いつ・何を・どの順で」だけを書き、「なぜ／具体的な型・関数名・設定例」は references/ へ逃がす。

### 全文書を貫く二軸モデル

| | `--keep-compat` 未指定 | `--keep-compat=<version>` 指定 |
|---|---|---|
| | **完全移行**（既定・主線） | **並走運用**（例外オプション） |
| 本命リスク | 依存パッケージの API 破壊（§6） | 下位互換破壊構文（§1） |
| 依存メジャーバンプ | 標準工程 | 原則据え置き |

フェーズ3 カテゴリ3〜6と目視確認2項目は**二軸に関わらず常時実施**。ここに条件分岐を持ち込まないこと。

### 唯一の失敗モード

ビルドもテストも無いため、**壊れても何のエラーも出ない**。実際の失敗は文書間の参照ズレ:

- `references/breaking-changes.md` の `§n` は SKILL.md から名指し参照されている → 節の挿入・並べ替えで全部ずれる
- SKILL.md のフェーズ番号は `breaking-changes.md` から逆参照されている
- README.md はフェーズ表・引数表・構成ツリーを SKILL.md からミラーしている

編集時は `.claude/docs/cross-references.md` のチェックリストを必ず実行する。

## Claude Code Reference Docs

詳細な技術リファレンスは `.claude/docs/` にある。これらを読む/更新するルールは `.claude/rules/` にある。
