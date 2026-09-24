# php-version-upgrade

WordPress の PHP バージョンアップを体系的に検証・修正する Claude Code スキルです。

## 概要

PHP のバージョンを上げるとき、Rector（PHP のコードを新しい書き方へ一括で書き換えるツール）の実行だけでは、次の2種類の問題が残ります。

### 修正漏れ

機械置換（ツールによる一括書き換え）では拾えない問題です。たとえば次のようなものがあります。

- 存在しない配列キーやプロパティを、確認せずに読み取っている
- `get_*_by()` のような「見つからなければ `false` を返す」関数の戻り値を、そのままプロパティ参照に使っている
- `null` を、`null` を受け付けない内部関数へ渡している
- 静的な文脈から非static メソッドを呼んでいる。PHP 7.x では警告で済んでいましたが、8.0 では Fatal エラー（処理を続行できずに停止するエラー）に変わります
- 使っているライブラリを新しいメジャーバージョンへ上げたら、関数名が変わっていた（依存パッケージの API 破壊）

### 過剰変換

逆に、書き換えすぎる問題です。`UP_TO_PHP_83`（Rector に「どのバージョン向けに書き換えるか」を指示する設定）は、その上限バージョンで初めて使える構文へのアップグレードまで行います。切替が終わるまで旧バージョンでも動かす必要がある場合、旧バージョン側でパースエラー（PHP がコードを読み込む段階で失敗し、その場でサイト全体が止まる状態）になり、本番障害に直結します。

このスキルは、「静的解析 → 人手レビュー → 実データ実行」の3層でこの両方を潰します。Rector だけ、テストだけ、といった単一の手法には頼りません。

## 前提

- **Claude Code**（対象は WordPress の PHP コードベースです）
- 静的解析ツール（アプリ本体とは別に、開発ツール用の composer 環境を作って導入してください）
  - [Rector](https://github.com/rectorphp/rector) — コードを新しい書き方へ一括で書き換えます
  - [PHPStan](https://phpstan.org/) + [szepeviktor/phpstan-wordpress](https://github.com/szepeviktor/phpstan-wordpress) — コードを実行せずに問題を洗い出します
  - [PHPCompatibility](https://github.com/PHPCompatibility/PHPCompatibility)（`squizlabs/php_codesniffer` + `phpcompatibility/php-compatibility`） — 指定した PHP バージョンで動くかを機械的に調べます
  - [jq](https://jqlang.github.io/jq/) — ゲート判定スクリプトが解析結果の JSON を読むために使います
- 対象の PHP バージョンを固定した実行環境（Docker / DDEV / Local 等）があると理想的です

**どのツールも「どのバージョンを入れるべきか」をバージョン番号では判断しません。** 導入したあとで `scripts/verify-gate.sh` を実行し、対象バージョンの非互換を実際に検出できるか（VERIFIED / DEGRADED / BLIND）で採否を決めます。バージョン番号で「このリリースなら大丈夫」と書くと、次のリリースで黙って弱いゲートになるためです。

## インストール

このスキルは [`tombolo-jp/cc-skills`](https://github.com/tombolo-jp/cc-skills) プラグインに含まれます。**クラウドセッション（claude.ai/code 等）でも使いたい場合はプラグインとして導入してください。**

```
/plugin marketplace add tombolo-jp/cc-task-skills
/plugin install cc-skills@tombolo-jp
```

導入方法の詳細（クラウドセッションでの有効化を含む）はリポジトリルートの [README](../../README.md) を参照してください。

プラグインを使わずこのスキル単体を置く場合は、すべてのプロジェクトで使うなら `~/.claude/skills/`、特定のプロジェクトだけで使うなら `<project>/.claude/skills/` にディレクトリごとコピーしてください。

## 使い方

Claude Code で、移行元と移行先の PHP バージョンを指定して起動します。引数はすべて任意です。

```
/php-version-upgrade [--target-paths=path1,path2] [--from=7.4] [--to=8.3] [--keep-compat=7.4]
```

| 引数 | 説明 |
|---|---|
| `--target-paths=<paths>` | 検証・修正する対象のパスです。複数指定するときはカンマで区切ります。省略すると git リポジトリのルート配下全体が対象になります。**指定は「対象を絞り込んでよい」という意味ではありません。** 指定した範囲の中は、これまでどおり全ファイルを候補にして進めます |
| `--from=<version>` | 移行元の PHP バージョンです。省略すると確認されます |
| `--to=<version>` | 移行先の PHP バージョンです。省略すると確認されます |
| `--keep-compat=<version>` | 旧バージョンと並走する期間がある場合の**例外オプション**です。切替が終わるまで動かし続ける必要がある下位バージョンを指定します。指定しなければ**完全移行**（旧バージョンを切り捨てる進め方）になります。こちらが既定で、大多数の移行が当てはまります |

例:

```
# 完全移行: 8.3 へ一本化します（対象は git リポジトリ全体）
/php-version-upgrade --from=7.4 --to=8.3
# 対象を明示する場合: 複数はカンマで区切ります
/php-version-upgrade --target-paths=wp-content/plugins/my-plugin,wp-content/themes/my-theme --to=8.3
# 並走運用: 切替が終わるまで 7.4 でも動かす必要がある場合。グロブや空白を含むパスはクォートで囲みます
/php-version-upgrade --target-paths='wp-content/plugins/*' --from=7.4 --to=8.3 --keep-compat=7.4
```

パスに空白が含まれる場合やグロブ（`*`）を使う場合は、値の全体をシングルクォートで囲んでください。**バッククォートは使わないでください。** シェルが中身をコマンドとして実行してしまいます。

## 進め方（フェーズ）

| フェーズ | 内容 |
|---|---|
| 0. ブランチ準備 | 現状を確認します。Rector が適用済みかどうかで、「自分で実行する」か「別ブランチをマージする」かに分かれます |
| 1. 静的解析セットアップ | PHPCompatibility（静的ゲート）と PHPStan を導入します。依存パッケージの API 破壊を検証するため、vendor の autoload とスタブも読ませます。PHPStan は level を最大にするだけでは未定義キーの読み取りを見落とすため、**level とは別の感度設定も有効にします** |
| 2. Rector 機械置換の実行 | まだ適用していなければ、**まず Rector を実行します**。危険なルール（第一級callable への変換等）を除外し、dry-run で確認してから本適用して、差分を人手でレビューします |
| 3. パターン別レビュー | 全クラスを対象に、未定義キー / null 引数 / 依存 API 破壊 / 静的呼び出しの Fatal 化などをカテゴリ別に精査します。あわせて、**どの静的解析でも検出できない類型**（無警告で結果だけが変わる比較セマンティクスの変更など）を目視で確認します |
| 4. 仕分けと修正 | まず **4-A 仕分け** で、検出した指摘を1件ずつ「実対応要 / 偽陽性 / 保留」へ判定し、根拠つきで台帳に記録します。**合格条件は「指摘 0 件」ではなく「未仕分け 0 件」です。** そのうえで **4-B 修正** を行い、修正のたびに静的ゲートを再実行して確認します |
| 5. 動作確認 | 静的ゲートを最終確認したうえで、実行環境で E2E 確認を行います。**バッチ / cron / CSV 出力は実データで実行します。** データの形によってだけ現れる警告は、これでしか見つかりません。実データ実行はメール送信や決済 API の呼び出しを実際に発生させるため、外部送信をブロックする手段を先に確認します |
| 6. 移行後フィードバック | 移行後に見つかった欠陥について、「なぜゲートが取りこぼしたのか」を分類コードで記録し、スキル自体の改善へ還流させます。実施しないと、同じ検出漏れが次の移行でそのまま再現します |

## 構成

```
php-version-upgrade/
├── SKILL.md                              # 手順本体
├── references/
│   ├── breaking-changes.md               # 破壊的変更カタログ（§7 は静的解析で検出できない類型）
│   ├── detection-gates.md                # 検出ゲートの守備範囲・感度・前提（数値はここが唯一の正）
│   ├── triage-ledger.md                  # 仕分け台帳のスキーマと規約
│   ├── triage-ledger-template.md         # 台帳の空雛形（コピーして使います）
│   ├── runtime-detection.md              # 実行時ログの設置・集計・撤去／移行先環境の実確認
│   ├── rector-config.md                  # Rector の推奨設定と「やりすぎ」の回避
│   └── wordpress-notes.md                # WordPress 固有の注意点（ACF の戻り値契約 / 偽陽性パターン集 等）
└── scripts/
    ├── lint-target-version.sh            # 指定した PHP バージョンでの一括構文互換チェック
    ├── probe-phpstan-levels.sh           # identifier ごとの下限 level をプロジェクトで実測します
    ├── phpstan-gate.sh                   # 「未仕分け 0 件」でゲート判定します（台帳との差集合）
    ├── verify-gate.sh                    # ゲートが実際に検出できるかを能動的に検証します
    ├── aggregate-migration-log.sh        # 実行時ログを集計します
    ├── correlate-static-runtime.sh       # 実行時ログと静的解析を突合します
    ├── php-migration-logger.php          # 実行時エラーロガー（汎用版）
    ├── php8-identifiers.txt              # identifier ホワイトリストの既定値
    ├── lib/find-bin.sh                   # バイナリ探索の共有関数（source して使います）
    ├── probes/                           # ゲート検証用の検体（解析させるためのもので、実行しません）
    ├── tests/                            # スクリプトの分岐回帰テスト
    └── wordpress/
        └── 00-php-migration-logger.php   # 実行時エラーロガー（WordPress 版）
```

## ライセンス

[GNU General Public License v3.0](LICENSE)（GPLv3）です。詳細は [LICENSE](LICENSE) を参照してください。
