# WordPress固有の注意点

WordPress上で動くコード（プラグイン・テーマ・must-use plugin）のPHPバージョンアップ対応で、他のPHPプロジェクトと異なる観点をまとめる。WordPress以外のプロジェクトではこのファイルは無視してよい。

## compat.phpによるポリフィル

`wp-includes/compat.php` は、WordPressが公式にサポートする最低PHPバージョンより新しいPHPの関数・機能をポリフィルしている（WordPress自体が幅広いPHPバージョンをサポートするため）。バージョン別の対応状況はWordPressのバージョンに依存するため、**「使っているWordPressの最低バージョンで、その関数がポリフィルされているか」を必ず確認**すること。

例（WordPress 5.9+）: `str_contains()` / `str_starts_with()` / `str_ends_with()`（いずれもPHP 8.0の関数）はポリフィルされているため、PHP 7.4環境でも安全に呼び出せる。PHPCompatibilityは「PHP 7.4に無い関数」として機械的にERROR判定するため、ポリフィル済みと確認できた箇所は書き換えず、インラインコメント（`// phpcs:ignore <sniff名> -- 理由`）でPHPCompatibilityの当該行だけを除外し、ゲートを通す。

## PHPStanのWordPress拡張

`szepeviktor/phpstan-wordpress` を使うと、WordPress関数のスタブ・フック（`add_action`/`add_filter`のコールバック戻り値検証等）を認識できる。導入時の注意:

- `phpstan.neon.dist` の `includes` に `vendor/szepeviktor/phpstan-wordpress/extension.neon` を追加する。
- `bootstrapFiles` に `vendor/autoload.php`（アプリ側のcomposer autoload）を指定する。
- 実際のWordPress本体・DB接続は不要（`php-stubs/wordpress-stubs` パッケージがスタブとして関数シグネチャを提供する）。

## `add_action` と `add_filter` は内部的に同一関数

WordPressコアでは `add_action()` は `add_filter()` のエイリアスとして実装されている（`do_action()`/`apply_filters()` も同様に、内部の同じフック管理機構を使う）。そのため、フィルターフック（値を返して使われるフック、例: `plugin_action_links`）に誤って `add_action()` で登録しても**動作はする**（戻り値も正しく使われる）。

ただし、PHPStanのWordPress拡張は関数名（`add_action` か `add_filter` か）からコールバックの用途を推測するため、`add_action()` で登録した関数が値を返していると「アクションコールバックは値を返すべきでない」という指摘が出る。この指摘が出た場合は、実際のフック名がフィルターかアクションかをWordPressコアのソース（`wp-includes/`）で確認し、登録関数を実態に合わせて修正するとよい（動作は変わらないが、意図が明確になり誤検知も消える）。

## `get_template_part()` の第3引数の型

WordPressコミュニティ製のスタブパッケージ（`php-stubs/wordpress-stubs`）は `get_template_part(string $slug, ?string $name = null, array $args = [])` と型宣言していることがあるが、**WordPressコア本体（`wp-includes/general-template.php`）の実装自体には型宣言がない**。`load_template()` も同様で、渡された `$args` をそのままrequire先のスコープへローカル変数として渡すだけであり、配列以外（文字列・オブジェクト等）を渡しても実行時エラーにはならない。

このため、PHPStanが「`$args` は配列であるべき」と指摘しても、それはスタブの型宣言がコア実装より厳格なだけであり、**実際にFatal Errorにはならない**。既存コードが意図的に文字列等を渡している場合は、実装を変更せず、根拠（コア実装を確認した旨）を添えてbaseline化してよい。

## テンプレートファイル内の`$args`未定義警告

`get_template_part($slug, $name, $args)` で渡した `$args` は、`load_template()` 内で該当テンプレートファイルのローカル変数としてそのまま利用可能になる（`extract()`ではなく、関数スコープの直接継承）。PHPStanは呼び出し元とテンプレートファイルの関係を静的に追跡できないため、テンプレートファイル内で `$args` を参照している箇所すべてで「変数が定義されていない可能性があります」という誤検知が出る。

対処: テンプレートファイル冒頭に型ヒントコメントを追加する。

```php
<?php
/** @var mixed $args get_template_part() の第3引数 */
$user = $args;
```

`$args` の実際の型が呼び出し元ごとに異なる場合（例: あるテンプレートはWP_Userオブジェクトを、別のテンプレートは文字列を渡す設計になっている場合）は、正直に `mixed` を使う。誤った narrow な型を宣言すると、後続のロジックの型チェックがかえって不正確になる。

## wp-config.php等、gitignore対象ファイルで定義される定数

本番の秘匿情報（APIキー等）を含む設定ファイル（`wp-config.php` 等）は通常gitignore対象で、静的解析の実行環境にも存在しないことがある。この場合、そこで定義される定数（`define('SOME_API_KEY', ...)` 等）をコードが参照していると、PHPStanは「定数が見つからない」と指摘する。

対処: 実際の値を含まないダミー定義のスタブファイルを作成し、`phpstan.neon.dist` の `bootstrapFiles` に追加する。

```php
<?php
// .phpstan/wp-config-constants.stub.php
// 静的解析用のダミー定義。実際の値は本番のwp-config.php（gitignore対象）で定義される。
if (!defined('SOME_API_KEY')) {
    define('SOME_API_KEY', '');
}
```

このスタブファイルは秘匿情報を含まないため、リポジトリにコミットしてよい。`wp-config.php` に新しい定数が追加されたら、このスタブファイルにも追記する運用とする。

## 外部API連携コードの重点確認

WordPressの `wp_remote_get()` / `wp_remote_post()` は、通信失敗時（タイムアウト・DNS失敗・SSL検証失敗等）に **`WP_Error` オブジェクトを返す**（配列ではない）。戻り値を `!empty($response)` のようなゆるい判定だけで「成功」と扱い、`$response['body']` 等の配列アクセスをそのまま行っていると、通信障害時に **`WP_Error` を配列アクセスしてFatal Error** になる。

外部APIのラッパー等、繰り返し使われる共通関数がこのパターンになっていないか重点的に確認する。修正は `is_wp_error($response)` によるガードを先頭に追加するだけで済むことが多いが、影響範囲（そのラッパーを呼んでいる全箇所）が広いため優先度は高い。

## ACF 関数の戻り値契約

**`php-stubs/acf-pro-stubs` の宣言を実読して確認した契約**（2026-08-05 / acf-pro-stubs）。**この stub が無いと、最大感度でもオフセットアクセス系の指摘は 0 件になる。** stub の有無はゲートの前提条件そのものである。

| 関数 | stub 上の戻り値 | 対象が無いとき | 検出可否 | 典型的な誤用 | 対処 |
|---|---|---|---|---|---|
| `get_field()` | **`mixed`** | `false`（フィールド未設定）／`null` | **★検出不能・目視必須。** `mixed` なので何をしても指摘されない | `get_field('image')['sizes']['large']` —— 未設定なら `false` へのオフセットアクセス | 取得直後に `is_array()` / `is_string()` で分岐する。`?? ''` だけでは `false` を素通しする |
| `get_fields()` | `array\|false` | **`false`** | `offsetAccess.nonOffsetAccessible`（union なので中程度の感度から） | `get_fields($id)['key']` を無ガードで参照 | `$f = get_fields($id); $f = is_array($f) ? $f : [];` を置き、以降は `$f['key'] ?? null` |
| `get_field_object()` | `array\|false` | **`false`** | 同上 | `get_field_object('x')['choices'][$k]` | `['choices'][$k] ?? ''` ではなく、まず `false` を弾く |
| `get_sub_field()` | `mixed` | `false` | **検出不能** | `get_field()` と同じ | 同上 |
| `have_rows()` | `boolean` | `false` | — | — | — |

> **`get_field()` が `mixed` であることが、この表の最大の情報である。** ACF を多用するコードでは、静的解析の「オフセットアクセス系 0 件」は**そのカテゴリを見ていないだけ**のことがある。`get_field()` の呼び出し箇所は**目視で列挙する**（`grep -n "get_field(" `）。

## 「対象が無ければ `false`/`null` を返す」WordPress 関数

戻り値をガードせずにプロパティ・オフセット参照すると、PHP 8.0 で Warning になる。**対象が存在しないデータでのみ顕在化する**ため、クリーンな少数データのテストでは出ない。

| 関数 | 対象が無いとき | よくある誤用 |
|---|---|---|
| `get_user_by()` | `false` | `get_user_by('email', $x)->ID` |
| `get_post()` / `get_page_by_path()` | `null` | `get_post($id)->post_title` |
| `get_userdata()` | `false` | `get_userdata($id)->user_email` |
| `get_term()` / `get_term_by()` | `null` / `false` / `WP_Error` | `get_term_by(...)->name` |
| `get_current_screen()` | `null`（フック外） | `get_current_screen()->base` |
| `wp_get_attachment_image_src()` | `false` | `wp_get_attachment_image_src($id)[0]` |
| `glob()`（PHP 標準だが同型） | `false`（I/O エラー時のみ） | `foreach (glob(...) as $f)` |

**代入と参照の間にガード（`if (!$user) { return; }` 等）が無いものを機械的に洗い出す。**

## PHPStan の偽陽性パターン集

判定根拠に `FP4 に該当` の形で引用できるよう、安定 ID を振ってある。**ID は末尾追加のみ。再利用しない。**

| # | パターン | PHPStan の指摘 | 偽陽性である理由 | 根拠種別 | 解消手段 | 修正後も残るか |
|---|---|---|---|---|---|---|
| FP1 | 特定のフック／条件分岐の中でのみ実行され、対象の存在が保証される | `property.nonObject` | `is_page()` ガード内では固定ページが必ず存在する。`current_screen` フック内では画面オブジェクトが非 null | 仕様 | 呼び出し元に PHPDoc で型を明示する | いいえ |
| FP2 | 直前の分岐が `never` を返す関数（`exit` する）で終了している | `property.nonObject` | その経路には到達しない | 到達不能 | 当該関数へ `never` 戻り値型を付ける | いいえ |
| FP3 | 呼び出し先が内部で存在確認し、無ければ終了している | `property.nonObject` | 間接的な早期終了を追跡できない | 到達不能 | 呼び出し先の戻り値型を明示する | いいえ |
| FP4 | `glob()` の `false` は I/O エラー時のみ | `foreach.nonIterable` | 対象ディレクトリが無い場合もマッチ 0 件の場合も `[]` を返す（実測確認済み） | 実測 | ガード追加（下記の但し書きを参照） | いいえ |
| FP5 | 三項演算子・論理演算子の短絡で評価されない | `offsetAccess.nonOffsetAccessible` | 左辺が偽なので右辺は評価されない（実測確認済み） | 実測 | — | いいえ |
| FP6 | ガードを追加したが、ガード対象と参照対象の**同一性**を追跡できない | `offsetAccess.*` | `is_array($values)` で `continue` しているが、PHPStan は `$values` と `$cycle[$order]` が同じものだと分からない | 到達不能 | 中間変数を使わず直接参照する | **はい** |
| FP7 | ガード済みだが `mixed` の厳格化で報告が残る | `offsetAccess.*` on `mixed` | `?? ''` を適用済みで実行時に警告は出ない。高い感度で `mixed` 由来の報告だけが残る | 仕様 | 型注釈を付ける | **はい** |
| FP8 | stub の型宣言がコア実装より厳格 | `argument.type` 等 | コア実装には型宣言が無く、実行時エラーにならない | 仕様 | 根拠を明記して baseline 化する | **はい** |

**`修正後も残るか = はい` の行が、「未仕分け 0 件」ゲートを必要とする直接の理由である。** これらは何をしても消えないため、「指摘 0 件」を合格条件にすると永久に緑にならず、ゲート自体が無効化される。

> **FP4 の補足（偽陽性だが影響が甚大な唯一の実例）**: 万一 `glob()` が `false` を返すと mu-plugin のクラスが1つも読み込まれず**サイト全体が Fatal** になる。発生確率は極めて低いものの、影響が甚大なため**保険としてのガード追加を検討する価値はある**。「偽陽性だから対応不要」で機械的に閉じない類型として記録しておく。

## `wp_debug_mode()` の実挙動

`wp-includes/load.php` の `wp_debug_mode()` を実読して確定した事実（WordPress のソースを直接確認）。

| # | 事実 | 帰結 |
|---|---|---|
| 1 | `WP_DEBUG=false` の分岐に **`display_errors` を触るコードが無い** | php.ini の値がそのまま生きる。**WordPress は本番で `display_errors` を Off にしてくれない** |
| 2 | `WP_DEBUG=false` の `error_reporting` に **`E_WARNING` が含まれる** | PHP 8.0 で E_NOTICE→E_WARNING に格上げされた類型が、7.4 では抑制されていたのに**移行と同時に一斉に通過する** |
| 3 | `display_errors=0` の強制は **REST / AJAX / JSON / XMLRPC 経路のみ** | **通常の HTML ページ表示経路は保護されない。** 直感（「壊れるのは JSON」）と逆に、情報露出が起きるのは普通のページである |
| 4 | `wp_debug_mode()` は `wp-settings.php` の**先頭付近で1回だけ**呼ばれ、mu-plugins のロードは**その後**である | その区間で出た警告は mu-plugin 版ロガーでは捕捉も抑止もできない。一方、mu-plugin の `ini_set()` は**後勝ちで有効になる**（`init` フックでの再適用は不要） |

つまり **「PHP 8 への移行」＋「WordPress の既定」＝「本番で Warning が画面に出る」が既定コンボ**である。

> **移行先環境のエラー表示設定は、推測せず必ず実測する。**「フレームワークが本番では出さないようにしているはず」は成り立たない。確認手順は `references/runtime-detection.md` §4。

## 実行時ログドロップイン（WordPress 版）の設置と撤去

汎用の手順・ログの読み方・撤去の検証は `references/runtime-detection.md`。ここには WordPress 固有の手順だけを書く。

**設置**

1. `scripts/wordpress/00-php-migration-logger.php` と `scripts/php-migration-logger.php` の**2ファイルを対で** `wp-content/mu-plugins/` へ置く。
2. `wp-config.php` に定数を定義する。**`PHP_MIGRATION_EXPIRE`（撤去期限）は必須**である。

```php
define('PHP_MIGRATION_LOG', '/var/log/php-migration/site.log'); // ★ docroot 外
define('PHP_MIGRATION_ROOT', ABSPATH);
define('PHP_MIGRATION_OWN_PATHS', ABSPATH . 'wp-content/mu-plugins/myplugin,' . ABSPATH . 'wp-content/themes/mytheme');
define('PHP_MIGRATION_EXPIRE', '2026-09-30');
```

3. `scripts/verify-gate.sh --gate=logger` で VERIFIED を確認してから運用に入る。

| 規定 | 理由 |
|---|---|
| **`WP_CONTENT_DIR . '/debug.log'` を出力先にしない** | `wp-content/` は Web 配信対象。`.htaccess` の書き換えルールは実在ファイルを素通しするのが一般的で、**置けば HTTP で取得できる** |
| docroot 外へ置けない場合は、`curl -I <URL>` で 403/404 を確認するまで有効化しない | 「置けないから中に置いた」で終わると恒久的な情報公開になる |
| `PHP_MIGRATION_OWN_PATHS` を必ず設定する | 未設定だと `own:<unconfigured>` になり、「自社コードのどこを直すか」が出ない。**ロガーは推測で埋めない**（誤った `own` は検出漏れそのものになる） |
| mu-plugin 版の限界を報告に明記する | `wp_debug_mode()` から mu-plugins ロードまでの区間は捕捉できない。黙っておくと「0 件＝安全」の誤読が起きる |

**`WP_DEBUG` との関係（このロガーを入れる価値そのもの）**: `WP_DEBUG=false` でも `error_reporting` には E_WARNING が含まれ、かつ PHP はマスクの有無に関係なくエラーハンドラを呼ぶ（PHP 8.3.23 実測確認済み）。したがって**ロガーは `WP_DEBUG` の値によらず同じものを拾う。**「WP_DEBUG=false だから警告は出ていない」は成り立たない。

**撤去**: 2ファイルと `wp-config.php` の定数を削除し、**本番に無いことを確認する**（`wp eval 'var_dump(file_exists(WPMU_PLUGIN_DIR . "/00-php-migration-logger.php"));'`）。「デプロイした」ではなく「本番に無い」を確認する。収集済みログの退避と削除まで含めて撤去である。
