# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

このリポジトリは Claude Code 用のカスタムスキル集であり、**アプリケーションではなくスキルそのもの**です。同時に、リポジトリ自体がプラグイン（`cc-skills`）として機能します。これにより、手元の Claude Code だけでなく**クラウドセッション（claude.ai/code 等）からも同じスキルを利用できます**。

マーケットプレイス定義（`tombolo-jp`）は本リポジトリではなく [`tombolo-jp/cc-task-skills`](https://github.com/tombolo-jp/cc-task-skills) の `.claude-plugin/marketplace.json` にあり、そこから `cc-task-skills` と `cc-skills` の2プラグインが配布されます。**マーケットプレイスは名前で一意に識別され、同名のものを追加すると後勝ちで置き換わる**ため、`tombolo-jp` を名乗る定義は1箇所に限り、スキル集はその下にプラグインとしてぶら下げます。本リポジトリに `marketplace.json` を置いてはいけません。

## リポジトリ構成

| パス | 役割 |
|---|---|
| `.claude-plugin/plugin.json` | プラグイン定義。`name` は `cc-skills`。マーケットプレイス定義はここには置かない（上記参照） |
| `skills/<skill>/SKILL.md` | 各スキルの**仕様の正本**であり実行エントリポイント。frontmatter の `name` はディレクトリ名と一致させる |
| `skills/<skill>/references/*.md` | SKILL.md から切り出した規約。該当フェーズに着手した時点でのみ読み込む |
| `skills/<skill>/templates/*` | 生成物のテンプレート。生成の直前に読み込む |
| `skills/<skill>/scripts/*` | スキルが呼び出す補助スクリプト |
| `README.md` | 利用者向けドキュメント（導入手順・クラウドセッションでの制約） |

## マーケットプレイスへの登録内容

`tombolo-jp/cc-task-skills` の `.claude-plugin/marketplace.json` の `plugins` 配列に、本リポジトリが次のエントリとして登録されています。プラグイン名や説明を変えるときは、そちらも合わせて更新してください。

```json
{
  "name": "cc-skills",
  "source": {
    "source": "github",
    "repo": "tombolo-jp/cc-skills"
  },
  "description": "PHPバージョンアップ・DDEV/Colima 環境構築・ブラウザ自動操作・プロジェクト文書整備を支援する Claude Code スキル集",
  "category": "development",
  "keywords": ["php", "wordpress", "ddev", "colima", "playwright", "documentation"]
}
```

## スキルを追加・変更するときの規約

1. **配置は `skills/<skill-name>/SKILL.md` に固定する。** プラグインのスキル探索はこのパスを前提とします。リポジトリ直下に置いたスキルはプラグインとして読み込まれません。
2. **frontmatter の `name` はディレクトリ名と一致させる。** 一致していれば `/cc-skills:<name>` の短縮形 `/<name>` も使えます。
3. **`description` には発火トリガーを含める。** 日本語スキルでは「トリガー: ...」の形で代表的な呼び出し語を列挙します。
4. **`allowed-tools` はカンマ区切りで書く。** 空白区切りは解釈されません。
5. **スキル自身のディレクトリを参照するときは導入方法に依存しない書き方をする。** 導入経路によって実体パスが変わるため、`~/.claude/skills/<name>/` と決め打ちしないこと。プラグイン導入時は `${CLAUDE_PLUGIN_ROOT}/skills/<name>/`、コピー導入時は `~/.claude/skills/<name>/` になります。
6. **スキルを追加したら `README.md` の「収録スキル」表と「クラウドセッションでの注意点」を更新する。** `plugin.json` は個々のスキルを列挙しないため変更不要です。`cc-task-skills` 側の `marketplace.json` も、プラグイン単位の登録なので変更不要です。

## クラウドセッションを前提にした記述

スキルの手順を書くときは、クラウドセッションで成立するかどうかを必ず検討してください。

- **コンテナは破棄される。** 成果物を残すにはコミットが必要です。手順の最後に「コミットが必要」と明示してください。
- **ローカル固有の前提（macOS / Docker / Colima / GUI）はクラウドに無い。** 前提が欠ける場合は、**何をどこまでできるか**を切り分けて SKILL.md に書きます（例: `ddev-colima-setup` は「生成まではクラウド、起動は手元の macOS」）。
- **外部ツールの有無で分岐する箇所は、停止条件を明示する。** 中途半端な生成物を残さず、前提チェックの段階で止めます。
- **実験的機能（Agent Teams 等）は既定で無効。** ツールが無い場合のフォールバック手順を SKILL.md に書き、ユーザーに有効化を求めて停止しないこと。

## ライセンス

GPL-3.0
