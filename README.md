# CC Skills

Claude Code 用のカスタムスキル集です。PHP バージョンアップ対応、DDEV + Colima のローカル開発環境構築、ブラウザ自動操作、プロジェクト文書の整備、Figma デザインからのコーディングを、それぞれ 1 コマンドで進められます。

## 収録スキル

| スキル | 概要 | クラウドセッション |
|---|---|---|
| [`/php-version-upgrade`](skills/php-version-upgrade/) | PHP バージョンアップの修正漏れ・過剰変換を「静的解析 → レビュー → 実行時検証」の3層で潰す | 利用可（PHPStan / PHPCS / jq が入る環境なら） |
| [`/ddev-colima-setup`](skills/ddev-colima-setup/) | macOS (Apple Silicon) 向けに DDEV + Colima の WordPress 環境一式を生成する | **生成まで**（起動は手元の macOS） |
| [`/playwright-cli`](skills/playwright-cli/) | `playwright-cli` によるブラウザ操作・Web ページのテスト | 利用可（ヘッドレスのみ） |
| [`/setup-project-docs`](skills/setup-project-docs/) | コードベースを解析し `.claude/docs/` `.claude/rules/` と `CLAUDE.md` を整備する | 利用可 |
| [`/figma-coding`](skills/figma-coding/) | Figma MCP で読み取ったデザインを実装する際の規約・チェックリスト集（取得→記録→実装→検証） | 利用可（Figma PAT を環境変数で渡す必要あり） |

## インストール

導入方法は2通りあります。**クラウドセッション（claude.ai/code 等）でも使いたい場合は方式Aを選んでください。** クラウドセッションは手元の `~/.claude/skills` を読まないため、方式Bではスキルが読み込まれません。

| | 方式A: プラグイン | 方式B: 個人スキルへコピー |
|---|---|---|
| クラウドセッション | **利用可** | 利用不可 |
| 更新 | `/plugin marketplace update` | 再コピー |
| チームで共有 | リポジトリの `.claude/settings.json` で共有可 | 各自で手動コピー |

> **両方を同時に導入しないでください。** 詳細は後述「[方式Aと方式Bの併用について](#方式aと方式bの併用について)」。

### 方式A: プラグインとして導入（推奨）

このリポジトリはプラグイン（`cc-skills`）として、マーケットプレイス **`tombolo-jp`** から配布されます。マーケットプレイスの定義は [`tombolo-jp/cc-task-skills`](https://github.com/tombolo-jp/cc-task-skills) リポジトリの `.claude-plugin/marketplace.json` に置かれており、`cc-task-skills` と `cc-skills` の2つのプラグインを収録しています。

> **なぜマーケットプレイスが別リポジトリにあるのか**: 1つのマーケットプレイスは複数のプラグインを収録でき、各プラグインの実体は別リポジトリでも構いません。一方で**マーケットプレイスは名前で一意に識別され、同名のものを追加すると後から追加した方が前のものを置き換えます**。そのため `tombolo-jp` という名札は1箇所だけが名乗り、スキル集はその下にプラグインとしてぶら下げる構成にしています。スキル集が増えてもマーケットプレイスは1つのままです。

> **前提**: 上記のマーケットプレイス登録（`cc-task-skills` 側の `marketplace.json` への `cc-skills` エントリ追加）が済んでいる必要があります。未登録の場合、`/plugin install cc-skills@tombolo-jp` はプラグインを見つけられません。

**A-1. 手元の Claude Code に導入する（ローカル）**

Claude Code 上で以下を実行します：
```
/plugin marketplace add tombolo-jp/cc-task-skills
/plugin install cc-skills@tombolo-jp
```

`marketplace add` に指定するのは `cc-task-skills` リポジトリですが、これは**マーケットプレイス定義の置き場所**を指しているだけで、`cc-task-skills` プラグイン自体が導入されるわけではありません。両方を使いたい場合は `/plugin install cc-task-skills@tombolo-jp` も続けて実行します。

既定で user スコープ（`~/.claude/settings.json`）に記録されるため、**一度実行すれば手元の全プロジェクトで使えます**。プロジェクトごとの設定は不要です。

> **前提: GitHub への SSH 接続が必要です（ローカル導入のみ）。** プラグイン本体のクローンは
> `git@github.com:tombolo-jp/cc-skills.git` の形式で実行されるため、SSH 鍵が未設定だと
> 次のように失敗します。**リポジトリは public ですが、HTTPS ではクローンされません。**
>
> ```
> ✘ Failed to install plugin "cc-skills@tombolo-jp": Failed to clone repository:
> git@github.com: Permission denied (publickey).
> ```
>
> エラー文面は「リポジトリが存在しないか権限が無い」と読めますが、原因は SSH 鍵です。
> 未設定の場合は [GitHub の手順](https://docs.github.com/authentication/connecting-to-github-with-ssh)
> に従って鍵を作成・登録したうえで、**プラグイン導入より先に一度**次を実行してください。
>
> ```bash
> ssh -T git@github.com   # Hi <ユーザー名>! ... と出れば成功（終了コード 1 は正常）
> ```
>
> **この事前接続は省略できません。** クローン時の ssh は `BatchMode=yes` /
> `StrictHostKeyChecking=yes` で起動するため、`~/.ssh/known_hosts` に github.com が
> 無いとホストキーの確認プロンプトを出せずに失敗します。鍵を登録しただけでは足りません。
>
> なお A-2 のクラウドセッションではこの準備は不要です（コンテナ側で認証されます）。

**A-2. クラウドセッションで使う**

クラウドセッションは毎回まっさらな VM でリポジトリをクローンして起動するため、**手元の `~/.claude` の設定は一切引き継がれません**。A-1 を実行済みでもクラウドには反映されないので、以下のどちらかが別途必要です。クラウドセッションでは `/plugin` コマンド自体が使えないため、セッション内で後から導入することもできません。

| | 適用範囲 | 設定場所 |
|---|---|---|
| **A-2-1. リポジトリに設定を置く** | そのリポジトリのみ | 利用側リポジトリの `.claude/settings.json`（要コミット） |
| **A-2-2. クラウド環境のセットアップスクリプト** | **全リポジトリ** | claude.ai のクラウド環境設定 |

チームで共有したいなら A-2-1、自分ひとりで全プロジェクトに効かせたいなら A-2-2 が向いています。併用もできます。

**A-2-1. リポジトリに設定を置く（そのリポジトリのメンバー全員に行き渡る）**

スキルを使いたい**プロジェクト側**のリポジトリに `.claude/settings.json` を作成し、以下を記述して**コミット・プッシュ**します：
```json
{
  "extraKnownMarketplaces": {
    "tombolo-jp": {
      "source": {
        "source": "github",
        "repo": "tombolo-jp/cc-task-skills"
      }
    }
  },
  "enabledPlugins": {
    "cc-skills@tombolo-jp": true
  }
}
```

リポジトリごとに1回コミットするだけで、以後そのリポジトリのクラウドセッションでは自動的に有効になります。設定がリポジトリに入るため、同じリポジトリで作業するメンバー全員に同じスキルが行き渡ります。

[`cc-task-skills`](https://github.com/tombolo-jp/cc-task-skills) と併用する場合も、マーケットプレイスは同じ1つなので `enabledPlugins` に1行足すだけです：
```json
{
  "extraKnownMarketplaces": {
    "tombolo-jp": {
      "source": { "source": "github", "repo": "tombolo-jp/cc-task-skills" }
    }
  },
  "enabledPlugins": {
    "cc-skills@tombolo-jp": true,
    "cc-task-skills@tombolo-jp": true
  }
}
```

**A-2-2. クラウド環境のセットアップスクリプトで導入する（全リポジトリに効く）**

クラウド環境（Environment）はリポジトリに紐づかず、ブラウザ・デスクトップアプリ・モバイル・`claude --cloud`・Routines のすべてで共有されます。そのため環境側に仕込んでおけば、**利用側リポジトリに何も置かずに全プロジェクトで使えます**。

claude.ai のクラウド環境設定を開き、**Setup script** 欄に以下を記述します：
```bash
#!/bin/bash
claude plugin marketplace add tombolo-jp/cc-task-skills --scope user || true
claude plugin install cc-skills@tombolo-jp --scope user || true
# cc-task-skills も使う場合は次の行も追加する
# claude plugin install cc-task-skills@tombolo-jp --scope user || true
```

- セットアップスクリプトは **Claude Code の起動前**に root 権限で実行され、書き込んだ内容は環境キャッシュに保持されます。
- **`|| true` は省略しないでください。** セットアップスクリプトが非ゼロで終了すると、セッション自体が起動しなくなります。
- 環境のネットワークアクセスは既定の **Trusted** 以上が必要です（GitHub への到達が必要なため）。
- セットアップスクリプトを変更すると環境キャッシュが再構築され、スクリプトが再実行されます。プラグインを最新化したいときはこれを利用できます。

**A-3. スキルの呼び出し名**

プラグイン経由で導入した場合、正式名は `/cc-skills:<スキル名>` 形式になります：
```
/cc-skills:php-version-upgrade --from=7.4 --to=8.3
/cc-skills:setup-project-docs
```

ただし各スキルは frontmatter の `name` をディレクトリ名と一致させているため、**他に同名のコマンドが無ければ短縮形も動作します**：
```
/php-version-upgrade --from=7.4 --to=8.3
/setup-project-docs
```

本 README の以降の記述はすべて短縮形で表記しています。短縮形が他のコマンドと衝突する場合は `/cc-skills:` を前置してください。

**A-4. 更新する**

プラグインはバージョン番号を持たず、コミット SHA で更新が判定されます。最新化するには：
```
/plugin marketplace update tombolo-jp
```

### 方式B: 個人スキルとしてコピー

1. このリポジトリをクローンします：
```bash
git clone https://github.com/tombolo-jp/cc-skills.git
```

2. Claude Code のスキルディレクトリにコピーします：
```bash
cp -r cc-skills/skills/* ~/.claude/skills/
```

特定のプロジェクトだけで使う場合は、コピー先を `<project>/.claude/skills/` にしてください。

> **`/figma-coding` は MCP サーバーに依存します。** どちらの方式で導入しても、スキル本体は MCP サーバーを同梱しません。利用側リポジトリの `.mcp.json` に `figma-developer-mcp` を登録し、Figma の PAT を環境変数で渡してください（雛形は `skills/figma-coding/templates/mcp.json.example`。`.mcp.json` 自体は `.gitignore` に入れ、コミットするのは雛形の側です）。MCP が使えない場合、スキルは推測で値を埋めず、手動採寸へ切り替えるか停止します。

### 方式Aと方式Bの併用について

**同一環境で方式Aと方式Bを併用しないでください。** 両方を導入すると `php-version-upgrade` などの短縮名を持つコマンドが二重に登録され、Claude Code は**先に見つかった方を警告なしに採用**します。どちらが起動したかは表示されないため、片方だけを更新した場合に古い定義が黙って使われ続けることがあります。

方式Aへ移行する場合は、先に個人スキル側を削除してください：
```bash
rm -rf ~/.claude/skills/php-version-upgrade ~/.claude/skills/ddev-colima-setup \
       ~/.claude/skills/playwright-cli ~/.claude/skills/setup-project-docs \
       ~/.claude/skills/figma-coding
```

### 共通の設定

**（`/setup-project-docs` を使う場合）Agent Teams を有効化する**

`/setup-project-docs` は解析フェーズで `TeamCreate` による並列探索を行います。Agent Teams は実験的機能のため、`~/.claude/settings.json` に以下を追加してください：
```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

未設定の場合、スキルは `TeamCreate` を使わず、同じ3観点の探索を通常の並列 `Agent` 呼び出し（`subagent_type: "Explore"`）へフォールバックします。並列性は保たれ、成果物も同じものが得られます。

> **クラウドセッションの場合**: `~/.claude/settings.json` には手が届きません。クラウド環境設定の **Environment variables** 欄に `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` を追加するか、利用側リポジトリの `.claude/settings.json` に同じ `env` ブロックを書いてコミットしてください。

## クラウドセッションでの注意点

方式Aでクラウドセッションから利用する場合、スキルごとに以下の制約があります。

**共通**

- **コンテナは破棄されます。** スキルが生成したファイル（設定一式・ドキュメント・修正差分）を残すには**コミットとプッシュが必要**です。
- **ネットワークは環境のポリシー配下です。** 外部へ到達できないときは、環境設定のネットワークアクセス（既定は Trusted）を確認してください。

**`/php-version-upgrade`**

- PHPStan / PHPCS + PHPCompatibility / jq / `php` 実行環境が必要です。クラウドセッションにこれらが無い場合は、環境の **Setup script** で導入するか、利用側リポジトリの `composer.json` の dev 依存として入れてください。
- 実行時検出フェーズ（実データでの動作ログ収集）は本番相当の WordPress 環境を前提とするため、クラウドセッションでは**静的解析とレビューのフェーズまで**が現実的な範囲です。

**`/ddev-colima-setup`**

- Colima も DDEV も macOS も無いため、クラウドでできるのは `scripts/generate.sh` による**設定一式の生成とコミット**までです。`colima start` / `ddev start` は手元の macOS で実行してください。

**`/playwright-cli`**

- クラウドコンテナには Chromium が同梱されており、`PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers` で参照されます。**`playwright install` は実行しないでください**（`npm install -g @playwright/cli@latest` だけで足ります）。
- ヘッドレス実行のみです。`--headed` は使えないため、ページの状態は `snapshot` で読み取ってください。

**`/figma-coding`**

- **本リポジトリで初めて MCP サーバーに依存するスキルです。** Figma MCP（`figma-developer-mcp`）が接続されていない環境では、スキルは値を推測せず、①`.mcp.json` を設定して再起動するか、②人が採寸・書き出しを供給する手動モードに切り替えるか、を確認して停止します。
- **PAT は環境変数で渡します。** クラウドセッションには手元の `.env` が無いため、クラウド環境設定の **Environment variables** 欄に `FIGMA_API_KEY` を設定するか、**Setup script** で環境変数を用意してください。`.mcp.json` に実値を書かないでください。
- **コミットするのは `.mcp.json.example` の側です。** `.mcp.json` は `.gitignore` に入れます（トークンが紛れ込むのは常に作業用ファイルの側のため）。クラウドセッションは手元の設定を引き継がないので、**セッション開始後にリポジトリのルートで `cp .mcp.json.example .mcp.json` を実行**してから使ってください。Setup script は環境単位でキャッシュされ**特定リポジトリのディレクトリを前提にできない**ため、この 1 行はセッション側で実行します（どうしても Setup script に置く場合は、非ゼロ終了でセッションが起動しなくなるのを避けるため `[ -f .mcp.json.example ] && cp .mcp.json.example .mcp.json || true` の形にしてください）。PAT を渡すのは Environment variables 側の役割で、こちらとは独立です。
- **コンテナは破棄されます。** 記録文書（node-map / design-spec / 比較資料）と書き出した画像は、コミットしない限り残りません。
- **検証工程はブラウザ自動化ツールに依存しません。** 手順として書かれているため、`/playwright-cli` は一例であり、セッションにあるツール（ヘッドレスを含む）で実施できます。

## リポジトリ構成

```
cc-skills/
├── .claude-plugin/
│   └── plugin.json               # プラグイン定義（cc-skills）
│                                 # マーケットプレイス定義 (tombolo-jp) は
│                                 # tombolo-jp/cc-task-skills 側に置かれている
├── skills/
│   ├── ddev-colima-setup/
│   ├── figma-coding/
│   ├── php-version-upgrade/
│   ├── playwright-cli/
│   └── setup-project-docs/
├── CLAUDE.md
├── LICENSE
└── README.md
```

各スキルは `SKILL.md`（実行エントリポイント）を持ち、必要に応じて `references/`（フェーズ着手時に読む規約）、`templates/`（生成物の雛形）、`scripts/`（補助スクリプト）を伴います。

## ライセンス

GPL-3.0。詳細は [LICENSE](LICENSE) を参照してください。

## 作者

[Yuki Kokubo](https://github.com/tombolo-jp)
