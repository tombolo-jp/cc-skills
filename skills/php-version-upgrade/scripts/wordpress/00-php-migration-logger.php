<?php
/**
 * PHP バージョン移行のための実行時エラーロガー（**WordPress 専用**）
 *
 * ★ WordPress 専用である。素の PHP 環境では `../php-migration-logger.php` を使うこと。
 *   このファイルは WordPress の定数・関数に依存する。
 *
 * ファイル名の `00-` は、mu-plugins のアルファベット順ロードで最初に来させるため。
 *
 * 使い方（設置場所と捕捉範囲）:
 *   | 設置 | 捕捉範囲 | 難易度 |
 *   |---|---|---|
 *   | wp-content/mu-plugins/00-php-migration-logger.php | mu-plugins ロード以降。**推奨** | 低 |
 *   | wp-config.php の `require ABSPATH . 'wp-settings.php';` 直前へ require | WP 初期化のほぼ全域 | 中 |
 *   | auto_prepend_file | リクエスト最初期から全域 | 高 |
 *
 * ★★ mu-plugin 版の限界（黙っておくと「0件＝安全」の誤読が起きる）★★
 *   `wp-settings.php` の `wp_debug_mode()`（85行目付近）から
 *   mu-plugins のロード（498行目付近）までの区間で出た警告は、
 *   **捕捉も抑止もできない。** この区間を含めたい場合は wp-config.php 版か
 *   auto_prepend_file 版を使うこと。
 *
 * 前提（wp-config.php で定義する）:
 *   define('PHP_MIGRATION_LOG', '/var/log/php-migration/site.log');  // ★ docroot 外
 *   define('PHP_MIGRATION_ROOT', ABSPATH);
 *   define('PHP_MIGRATION_OWN_PATHS', ABSPATH . 'wp-content/mu-plugins/myplugin,' . ABSPATH . 'wp-content/themes/mytheme');
 *   define('PHP_MIGRATION_EXPIRE', '2026-09-30');  // ★ 必須。撤去期限
 *
 *   ★ `PHP_MIGRATION_LOG` に `WP_CONTENT_DIR . '/debug.log'` を使わないこと。
 *     `wp-content/` は Web 配信対象であり、ログが HTTP で取得可能になる。
 *     docroot 外へ置けない場合は、`curl -I <URL>` で 403/404 を確認するまで有効化しない。
 *
 * 動作:
 *   汎用版（`../php-migration-logger.php`）を読み込み、WordPress 固有の
 *   実行コンテキスト判定だけを上乗せする。エラー処理の中身は汎用版と同一であり、
 *   **記録するだけで挙動を変えない**（`set_error_handler` は必ず `false` を返す）。
 *
 * WP_DEBUG との関係（**このロガーを入れる価値そのもの**）:
 *   `WP_DEBUG=false` でも `error_reporting` には E_WARNING が含まれ、
 *   かつ PHP はマスクの有無に関係なくエラーハンドラを呼ぶ（PHP 8.3.23 実測確認済み）。
 *   したがって**本ロガーは `WP_DEBUG` の値によらず同じものを拾う。**
 *   「WP_DEBUG=false だから警告は出ていない」は成り立たない。
 *
 * `display_errors` の扱い:
 *   `wp_debug_mode()` は `wp-settings.php:85` で**一度だけ**呼ばれ、mu-plugins のロードは
 *   同 498 行目である（WordPress のソースを実読して確認済み）。
 *   つまり `WP_DEBUG_DISPLAY` の適用は**このドロップインより前**に終わっている。
 *   よって汎用版が include 時に行う `ini_set('display_errors', '0')` が後勝ちで有効になる。
 *   **`add_action('init', ...)` で再適用する二段構えは不要である。**
 *
 * 撤去: `references/wordpress-notes.md`「実行時ログドロップイン（WordPress 版）の設置と撤去」。
 *   **削除ではなく「本番に無いこと」の検証で完了する。**
 */

if (!defined('ABSPATH')) {
    // WordPress 経由でない読み込みを弾く。直接 HTTP で叩かれても何もしない。
    return;
}

/**
 * 実行コンテキストを返す。汎用版がハンドラ内から呼ぶ。
 *
 * ★ 判定を mu-plugin のロード時点で行ってはならない。
 *   その時点では `wp_doing_ajax()` も `REST_REQUEST` もまだ確定していない。
 *   この関数は**エラーが起きた時点**で呼ばれるので、そこで初めて判定する。
 *
 * @return string
 */
function php_migration_logger_context()
{
    if (defined('WP_CLI') && WP_CLI) {
        return 'cli';
    }
    if (defined('DOING_CRON') && DOING_CRON) {
        return 'cron';
    }
    if (defined('REST_REQUEST') && REST_REQUEST) {
        return 'rest';
    }
    if (function_exists('wp_doing_ajax') && wp_doing_ajax()) {
        return 'ajax';
    }
    if (function_exists('is_admin') && is_admin()) {
        return 'admin';
    }
    return 'web';
}

// 汎用版を読み込む。**2ファイルを対で設置すること**（`00-php-migration-logger.php` と
// `php-migration-logger.php` の両方を mu-plugins へ置く）。
// mu-plugins 直下の `php-migration-logger.php` は WordPress にも直接ロードされるが、
// 汎用版は多重 include に対して安全（クラス宣言が条件付きのため二重初期化しない）。
$php_migration_generic = __DIR__ . '/php-migration-logger.php';
if (!file_exists($php_migration_generic)) {
    // スキルリポジトリ内から直接読む場合（scripts/wordpress/ → scripts/）。
    $php_migration_generic = dirname(__DIR__) . '/php-migration-logger.php';
}
if (!file_exists($php_migration_generic)) {
    // ★ 黙って何もしないと「ログが空＝警告0件＝安全」と誤読される。必ず痕跡を残す。
    error_log('[MIGRATION-LOGGER] 汎用版 php-migration-logger.php が見つかりません。ロガーは起動していません。');
    return;
}
require_once $php_migration_generic;
unset($php_migration_generic);

// ---- own_paths が未設定のときの「候補提示」 ----
//
// ★ 自動採用しない。誤った own は「vendor 由来だから無視」という判断を誘発し、
//   検出漏れそのものになる。ここでは候補をログに1行出すだけに留め、
//   採用は wp-config.php へ人が明示的に書くことで行う。
if (class_exists('PhpMigrationLogger', false)
    && (!defined('PHP_MIGRATION_OWN_PATHS') || PHP_MIGRATION_OWN_PATHS === '')
    && getenv('PHP_MIGRATION_OWN_PATHS') === false
) {
    $php_migration_candidates = array();
    if (defined('WPMU_PLUGIN_DIR')) {
        $php_migration_candidates[] = WPMU_PLUGIN_DIR;
    }
    if (defined('WP_PLUGIN_DIR')) {
        $php_migration_candidates[] = WP_PLUGIN_DIR;
    }
    if (defined('WP_CONTENT_DIR')) {
        $php_migration_candidates[] = WP_CONTENT_DIR . '/themes';
    }
    PhpMigrationLogger::hint(
        'PHP_MIGRATION_OWN_PATHS が未設定です。own は <unconfigured> のまま記録されます。'
            . ' wp-config.php で自社コードのパスを明示してください（自動採用はしません）。',
        array('candidates' => implode(',', $php_migration_candidates))
    );
    unset($php_migration_candidates);
}
