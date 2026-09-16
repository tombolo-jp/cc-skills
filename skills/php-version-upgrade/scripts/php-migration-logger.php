<?php
/**
 * PHP バージョン移行のための実行時エラーロガー（汎用版・フレームワーク非依存）
 *
 * 使い方:
 *   php.ini / .user.ini:  auto_prepend_file = /path/to/php-migration-logger.php
 *   もしくはアプリの最下層で:  require '/path/to/php-migration-logger.php';
 *
 * 前提:
 *   - **設置する前に、まず標準のエラーログで足りないかを検討すること。**
 *     本番で `display_errors=Off` かつ `error_log` が docroot 外で機能しているなら、
 *     標準ログを収集するだけで足りることが多い。自社コードのフレーム分離や
 *     実行コンテキスト判別が必要な場合にのみ、本ロガーを入れる。
 *     恒久的なリスクを負う前に、負わない道を先に検討する。
 *   - WordPress では `wordpress/00-php-migration-logger.php` を使うこと。
 *     このファイルは WordPress の関数を一切参照しない。
 *   - `PHP_MIGRATION_EXPIRE`（自己失効日）は**必須**。撤去を忘れても機能が止まるようにする。
 *
 * 設定（**定数 → 環境変数 → 既定** の順に解決する）:
 *   PHP_MIGRATION_LOG            出力先。既定は sys_get_temp_dir()。**docroot 内を既定にしない**
 *   PHP_MIGRATION_ROOT           ログ内パスの基準。静的解析との突合の要。既定 getcwd()
 *   PHP_MIGRATION_OWN_PATHS      自社コード判定のパス接頭辞（`,` 区切り）。**実質必須**
 *   PHP_MIGRATION_EXCLUDE_PATHS  自社コードから除く部分文字列（`,` 区切り）。既定 `/vendor/`
 *   PHP_MIGRATION_DEDUP          同一キーを何回まで即時出力するか。既定 1
 *   PHP_MIGRATION_BOOT_LOG       BOOT 行を出すか。既定 1（高トラフィックの Web では 0）
 *   PHP_MIGRATION_MAX_UNIQUE     1リクエストあたりのユニーク件数上限。既定 200
 *   PHP_MIGRATION_EXPIRE         自己失効日（YYYY-MM-DD）。**必須**
 *
 * 動作:
 *   `set_error_handler` で警告を LTSV へ記録する。**記録するだけで挙動を変えない。**
 *
 *   ★ ハンドラの引数は**ちょうど 4 個**。5 個目（$errcontext）を宣言してはならない。
 *     PHP 8 は 4 引数で呼ぶため、必須の 5 個目を宣言すると ArgumentCountError で **Fatal** になる。
 *   ★ 必ず `return false` する。`true` を返すと (1) E_USER_ERROR 等での処理停止を奪い、
 *     (2) 既定ハンドラが走らず error_log / APM への出力が消える
 *     ＝**移行のための計測が既存の監視を壊す**。
 *   ★ `error_reporting()` のマスクで**早期 return してはならない**。
 *     WP_DEBUG=false 等でマスクされた E_WARNING / E_DEPRECATED こそが拾いたいものである。
 *     マスクされていても PHP はハンドラを呼ぶ（PHP 8.3.23 実測確認済み）。
 *
 * ログに書かないもの（**最重要**）:
 *   $_POST / $_GET / $_COOKIE の値、Authorization ヘッダ、セッション ID、
 *   関数呼び出しの引数値、顧客 ID / 会員番号 / メールアドレス / 氏名 / 住所 / カード情報、
 *   クエリ文字列（トークンやメールアドレスが載る）、User-Agent、IP。
 *   本ロガーは「どこで警告が出たか」を知るためのものであって、
 *   「何が入っていたか」を知るためのものではない。両者を分けないと専用ログが個人情報の複製になる。
 *
 * 撤去: `references/runtime-detection.md` §5。**削除ではなく「不在の検証」で完了する。**
 */

// ★ クラス宣言を **if ブロックの中**に置くこと（多重 include 対策）。
//   トップレベルの無条件クラス宣言は PHP のコンパイル時に早期バインドされるため、
//   ファイル冒頭で `class_exists()` を見ても**初回ロードから true になり**、
//   その後の初期化処理へ到達しない。逆に条件を外すと、
//   auto_prepend_file と手動 require が重なったときに「Cannot redeclare」で Fatal になる。
//   条件付き宣言は早期バインドを抑止するので、両方を同時に満たせる。
//   （代替構文 `if (...) : ... endif;` を使うのは、クラス全体を字下げし直さないため。）
if (!class_exists('PhpMigrationLogger', false)) :

final class PhpMigrationLogger
{
    const VERSION = '1.0.0';

    /** @var bool 再入ガード。ハンドラ内から呼ぶ処理が再びエラーを出しても再帰しない */
    private static $inHandler = false;

    /** @var array<string,int> 重複抑制カウンタ。プロセス内（1リクエスト / 1CLI 実行）に限る */
    private static $seen = array();

    /** @var int このリクエストで記録したユニーク件数 */
    private static $uniqueCount = 0;

    /** @var bool 上限超過を記録済みか */
    private static $truncatedLogged = false;

    /** @var string */
    private static $logFile = '';

    /** @var string */
    private static $root = '';

    /** @var string[] 正規化済み（末尾 `/`）の自社コード接頭辞 */
    private static $ownPaths = array();

    /** @var string[] */
    private static $excludePaths = array();

    /** @var int */
    private static $dedup = 1;

    /** @var int */
    private static $maxUnique = 200;

    /** @var string このファイル自身の realpath。バックトレース先頭から捨てるために使う */
    private static $selfPath = '';

    /** @var int `@` 抑制時に error_reporting() が返す値 */
    private static $suppressMask = 0;

    /**
     * 設定を「定数 → 環境変数 → 既定」の順に解決する。
     * 定数を先に見るのは、wp-config.php 等から設定できるようにするため。
     *
     * @param string $name
     * @param string|null $default
     * @return string|null
     */
    private static function cfg($name, $default = null)
    {
        if (defined($name)) {
            return (string) constant($name);
        }
        $env = getenv($name);
        if ($env !== false && $env !== '') {
            return $env;
        }
        return $default;
    }

    /**
     * `,` 区切りの設定値を配列にする。空要素は捨てる。
     *
     * @param string|null $value
     * @return string[]
     */
    private static function splitList($value)
    {
        if ($value === null || $value === '') {
            return array();
        }
        $out = array();
        foreach (explode(',', $value) as $item) {
            $item = trim($item);
            if ($item !== '') {
                $out[] = $item;
            }
        }
        return $out;
    }

    /**
     * 接頭辞照合用にパスを正規化する。
     *
     * realpath でシンボリックリンクを解決し（macOS の /tmp → /private/tmp 等）、
     * **必ず `/` で終端させる**。終端しないと `/themes/rental` が
     * `/themes/rental-old` にも前方一致してしまう。
     *
     * @param string $path
     * @return string
     */
    private static function normalizePrefix($path)
    {
        $real = @realpath($path);
        if ($real === false) {
            $real = $path;
        }
        return rtrim($real, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;
    }

    /**
     * 初期化。設定解決・自己失効・display_errors 強制・BOOT 行の出力を行う。
     *
     * @return bool 起動したら true、失効等で起動しなかったら false
     */
    public static function boot()
    {
        // ---- 自己失効（フェイルセーフ） ----
        // 撤去を忘れても機能が止まる。期限が無い場合も起動しない（無期限の設置を作らない）。
        $expire = self::cfg('PHP_MIGRATION_EXPIRE');
        if ($expire === null || $expire === '') {
            error_log('[MIGRATION-LOGGER] PHP_MIGRATION_EXPIRE が未設定です。撤去期限の無い設置は行いません。');
            return false;
        }
        $expireTs = strtotime($expire . ' 23:59:59');
        if ($expireTs === false) {
            error_log('[MIGRATION-LOGGER] PHP_MIGRATION_EXPIRE の書式が不正です（YYYY-MM-DD）: ' . $expire);
            return false;
        }
        if (time() > $expireTs) {
            error_log('[MIGRATION-LOGGER] 期限切れ（' . $expire . '）。撤去してください。');
            return false;
        }

        self::$selfPath = (string) (@realpath(__FILE__) ?: __FILE__);
        self::$suppressMask = E_ERROR | E_CORE_ERROR | E_COMPILE_ERROR
            | E_USER_ERROR | E_RECOVERABLE_ERROR | E_PARSE;

        // ---- 出力先 ----
        // ★ docroot 内を既定にしない。既定を docroot 内にすると
        //   「動く場所に置く」ために恒久的な情報公開へ寄っていく。
        $logDefault = 0;
        $logFile = self::cfg('PHP_MIGRATION_LOG');
        if ($logFile === null || $logFile === '') {
            $logFile = rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR)
                . DIRECTORY_SEPARATOR . 'php-migration.log';
            $logDefault = 1;
        }
        self::$logFile = $logFile;

        $rootCfg = self::cfg('PHP_MIGRATION_ROOT');
        if ($rootCfg === null || $rootCfg === '') {
            $rootCfg = (string) getcwd();
        }
        self::$root = self::normalizePrefix($rootCfg);

        // ---- 自社コード判定 ----
        // ★ 未設定のとき wp-content/ 等を推測で既定にしない。
        //   誤った own は「vendor 由来だから無視」という判断を誘発し、検出漏れそのものになる。
        $ownRaw = self::splitList(self::cfg('PHP_MIGRATION_OWN_PATHS'));
        foreach ($ownRaw as $p) {
            self::$ownPaths[] = self::normalizePrefix($p);
        }
        $excludeRaw = self::cfg('PHP_MIGRATION_EXCLUDE_PATHS');
        self::$excludePaths = self::splitList($excludeRaw === null ? '/vendor/' : $excludeRaw);

        $dedup = self::cfg('PHP_MIGRATION_DEDUP', '1');
        self::$dedup = max(1, (int) $dedup);
        $maxUnique = self::cfg('PHP_MIGRATION_MAX_UNIQUE', '200');
        self::$maxUnique = max(1, (int) $maxUnique);

        // ---- display_errors の強制 ----
        // 目的は「出力破損の防止」であって「情報露出の停止」ではない。
        // 環境側の恒久設定の確認（references/runtime-detection.md §4）は別途必ず行う。
        //
        // ★ `return false` と `display_errors=0` はセットでしか成立しない。
        //   display_errors を落とさないと、return false により既定の表示処理も走って画面へ出る。
        $iniFailures = array();
        foreach (array(
            'display_errors' => '0',
            'display_startup_errors' => '0',
            'html_errors' => '0',
            'log_errors' => '1',
            'zend.exception_ignore_args' => '1',
        ) as $key => $value) {
            if (@ini_set($key, $value) === false) {
                $iniFailures[] = $key;
            }
        }

        // ---- BOOT 行 ----
        if (self::cfg('PHP_MIGRATION_BOOT_LOG', '1') !== '0') {
            $boot = array(
                'lv' => 'BOOT',
                'ver' => self::VERSION,
                'php' => PHP_VERSION,
                'sapi' => PHP_SAPI,
                'root' => self::$root,
                'own_paths' => (string) count(self::$ownPaths),
                'log_default' => (string) $logDefault,
                'expire' => $expire,
            );
            if ($iniFailures !== array()) {
                // ★ ini_set が効かない場合がある（php-fpm の php_admin_value で固定）。
                //   黙って「強制した気になる」のを防ぐため、失敗した項目を明示する。
                $boot['ini_failed'] = implode('/', $iniFailures);
            }
            if (self::$ownPaths === array()) {
                $boot['warn'] = 'own_paths_unset';
            }
            self::write($boot);
        }

        return true;
    }

    /**
     * LTSV の値をサニタイズする。
     * ラベル区切りの `:` は値側でエスケープしない（LTSV は最初の `:` のみを区切りとみなす）。
     *
     * @param string $value
     * @return string
     */
    private static function escape($value)
    {
        return str_replace(
            array("\\", "\t", "\n", "\r"),
            array("\\\\", '\t', '\n', '\r'),
            $value
        );
    }

    /**
     * 512 バイトで切る。マルチバイト文字の途中で切れた末尾は落とす
     * （壊れたバイト列をログに残さないため）。
     *
     * @param string $value
     * @return string
     */
    private static function truncate($value)
    {
        if (strlen($value) <= 512) {
            return $value;
        }
        $cut = substr($value, 0, 512);
        if (function_exists('mb_substr') && function_exists('mb_strlen')) {
            $cut = mb_substr($cut, 0, mb_strlen($cut, 'UTF-8'), 'UTF-8');
        }
        // 不完全な UTF-8 末尾を削る
        while ($cut !== '' && !preg_match('//u', $cut)) {
            $cut = substr($cut, 0, -1);
        }
        return $cut;
    }

    /**
     * 1行を LTSV で追記する。
     *
     * @param array<string,string> $fields
     * @return void
     */
    private static function write(array $fields)
    {
        $parts = array('time:' . date('c'));
        foreach ($fields as $label => $value) {
            $parts[] = $label . ':' . self::escape((string) $value);
        }
        $line = implode("\t", $parts) . "\n";

        $dir = dirname(self::$logFile);
        if (!is_dir($dir)) {
            @mkdir($dir, 0750, true);
        }
        $exists = file_exists(self::$logFile);
        // 並行リクエストがあるため LOCK_EX は必須。
        @file_put_contents(self::$logFile, $line, FILE_APPEND | LOCK_EX);
        if (!$exists) {
            // file_put_contents の作成モードは umask 依存で 0644 になりうる。明示的に落とす。
            @chmod(self::$logFile, 0640);
        }
    }

    /**
     * バックトレースから「自社コードの最深フレーム」を求める。
     *
     * 1. 先頭から、このロガー自身のフレームを捨てる
     * 2. 検査列 = [(errfile, errline)] + [各フレームの (file, line)]
     *    （エラー発生位置そのものが自社コードなら depth=0 で確定する）
     * 3. 上から順に、OWN_PATHS のいずれかに前方一致し、EXCLUDE_PATHS を含まない最初の要素を採用
     * 4. 見つからなければ `<none>`。**捏造しない。空文字にもしない。**
     * 5. 採用した位置を depth として併記する
     *
     * @param string $errfile
     * @param int $errline
     * @return array{0:string,1:int} [own, depth]
     */
    private static function ownFrame($errfile, $errline)
    {
        if (self::$ownPaths === array()) {
            return array('<unconfigured>', -1);
        }

        // DEBUG_BACKTRACE_IGNORE_ARGS は必須。既定では引数値が入り、
        // 個人情報がログへ流れ込む。深さ 30 の制限はコスト対策でもある。
        $frames = debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS, 30);

        $candidates = array(array($errfile, $errline));
        foreach ($frames as $frame) {
            if (!isset($frame['file'])) {
                continue;
            }
            if (@realpath($frame['file']) === self::$selfPath) {
                continue;
            }
            $candidates[] = array($frame['file'], isset($frame['line']) ? (int) $frame['line'] : 0);
        }

        $depth = 0;
        foreach ($candidates as $candidate) {
            $real = @realpath($candidate[0]);
            if ($real === false) {
                $real = $candidate[0];
            }
            $excluded = false;
            foreach (self::$excludePaths as $ex) {
                if (strpos($real, $ex) !== false) {
                    $excluded = true;
                    break;
                }
            }
            if (!$excluded) {
                foreach (self::$ownPaths as $own) {
                    if (strpos($real, $own) === 0) {
                        return array(self::relative($real) . ':' . $candidate[1], $depth);
                    }
                }
            }
            $depth++;
        }

        return array('<none>', -1);
    }

    /**
     * PHP_MIGRATION_ROOT からの相対パスへ落とす。突合の主キーになるため必ず通す。
     *
     * @param string $path
     * @return string
     */
    private static function relative($path)
    {
        if (self::$root !== '' && strpos($path, self::$root) === 0) {
            return substr($path, strlen(self::$root));
        }
        return $path;
    }

    /**
     * errno を LTSV のラベル値へ落とす。
     *
     * @param int $errno
     * @return string
     */
    private static function levelName($errno)
    {
        $map = array(
            E_ERROR => 'E_ERROR',
            E_WARNING => 'E_WARNING',
            E_PARSE => 'E_PARSE',
            E_NOTICE => 'E_NOTICE',
            E_CORE_ERROR => 'E_CORE_ERROR',
            E_CORE_WARNING => 'E_CORE_WARNING',
            E_COMPILE_ERROR => 'E_COMPILE_ERROR',
            E_COMPILE_WARNING => 'E_COMPILE_WARNING',
            E_USER_ERROR => 'E_USER_ERROR',
            E_USER_WARNING => 'E_USER_WARNING',
            E_USER_NOTICE => 'E_USER_NOTICE',
            E_RECOVERABLE_ERROR => 'E_RECOVERABLE_ERROR',
            E_DEPRECATED => 'E_DEPRECATED',
            E_USER_DEPRECATED => 'E_USER_DEPRECATED',
        );
        return isset($map[$errno]) ? $map[$errno] : ('E_UNKNOWN_' . $errno);
    }

    /**
     * 実行コンテキスト。汎用版は SAPI しか見ない（フレームワークに依存しないため）。
     *
     * フレームワーク固有の判別が要る場合は、このファイルを読み込む**前**に
     * `php_migration_logger_context()` を定義しておくと、その戻り値が使われる。
     * 判定は**ハンドラ内**（＝実際にエラーが起きた時点）で呼ばれるため、
     * ブート時点ではまだ未定義の定数・関数にも依存できる。
     *
     * @return string
     */
    protected static function context()
    {
        if (function_exists('php_migration_logger_context')) {
            $ctx = php_migration_logger_context();
            if (is_string($ctx) && $ctx !== '') {
                return $ctx;
            }
        }
        return PHP_SAPI === 'cli' ? 'cli' : 'web';
    }

    /**
     * 補助情報を1行記録する（`lv:HINT`）。
     *
     * **推定値を設定として自動採用させないための出口**である。
     * 「候補はこれです」とログに出すに留め、採用は人が明示的に行う。
     *
     * @param string $message
     * @param array<string,string> $extra
     * @return void
     */
    public static function hint($message, array $extra = array())
    {
        self::write(array_merge(array('lv' => 'HINT', 'msg' => self::truncate($message)), $extra));
    }

    /**
     * リクエストの**パス部分のみ**。クエリ文字列は記録しない
     * （トークン・メールアドレスが載るため）。
     *
     * @return string
     */
    private static function requestPath()
    {
        if (PHP_SAPI === 'cli') {
            return isset($_SERVER['PHP_SELF']) ? (string) $_SERVER['PHP_SELF'] : '<cli>';
        }
        if (!isset($_SERVER['REQUEST_URI'])) {
            return '<unknown>';
        }
        $path = parse_url((string) $_SERVER['REQUEST_URI'], PHP_URL_PATH);
        return is_string($path) ? $path : '<unknown>';
    }

    /**
     * エラーハンドラ本体。
     *
     * ★ 引数はちょうど 4 個。5 個目を宣言すると PHP 8 で Fatal（ArgumentCountError）。
     * ★ 必ず false を返す。
     *
     * @param int $errno
     * @param string $errstr
     * @param string $errfile
     * @param int $errline
     * @return bool
     */
    public static function handle($errno, $errstr, $errfile, $errline)
    {
        if (self::$inHandler) {
            return false;
        }
        self::$inHandler = true;

        try {
            // ★ ここでマスク判定による早期 return をしてはならない。
            //   慣用句の `if (!(error_reporting() & $errno)) return false;` を入れると、
            //   WP_DEBUG=false でマスクされた E_WARNING / E_DEPRECATED を落としてしまう。
            //   それこそが本ロガーで拾いたいものである。
            //   `@` 抑制かどうかは sup フィールドへ分離して記録する。
            $mask = error_reporting();
            $suppressed = ($mask === 0 || $mask === self::$suppressMask) ? '1' : '0';

            list($own, $depth) = self::ownFrame($errfile, $errline);
            $ownFile = $own;
            $ownLine = '';
            $sep = strrpos($own, ':');
            if ($sep !== false) {
                $ownFile = substr($own, 0, $sep);
                $ownLine = substr($own, $sep + 1);
            }

            // 重複抑制キーに own_file:own_line を含める。
            // 共有ヘルパの同一行が**別々の呼び出し元**から踏まれるのは別々の欠陥であり、
            // 含めないと N 箇所のうち1箇所しかログに残らない。
            // errstr は含めない（キー名が変わるたびに別件になり抑制が効かなくなる）。
            $key = $errno . '|' . $errfile . '|' . $errline . '|' . $ownFile . '|' . $ownLine;

            if (!isset(self::$seen[$key])) {
                if (self::$uniqueCount >= self::$maxUnique) {
                    // 想定外の暴発でディスクを埋めない。**捨てたことを必ず記録する**
                    //（黙って捨てると「0件＝問題なし」の再生産になる）。
                    if (!self::$truncatedLogged) {
                        self::write(array('lv' => 'DEDUP', 'truncated' => '1',
                            'max_unique' => (string) self::$maxUnique));
                        self::$truncatedLogged = true;
                    }
                    self::$inHandler = false;
                    return false;
                }
                self::$seen[$key] = 0;
                self::$uniqueCount++;
            }
            self::$seen[$key]++;

            if (self::$seen[$key] <= self::$dedup) {
                self::write(array(
                    'lv' => self::levelName($errno),
                    'ctx' => static::context(),
                    'sup' => $suppressed,
                    'own' => $own,
                    'depth' => (string) $depth,
                    'at' => self::relative((string) (@realpath($errfile) ?: $errfile)) . ':' . $errline,
                    'pid' => (string) getmypid(),
                    'req' => self::requestPath(),
                    'msg' => self::truncate($errstr),
                ));
            }
        } catch (Throwable $e) {
            // ロガーの不具合でアプリを止めない。
        }

        self::$inHandler = false;

        // ★ 必ず false。既定ハンドラへ処理を渡す。
        return false;
    }

    /**
     * Fatal の捕捉。
     *
     * ★ Fatal 行では own を解決できない（スタックが既に巻き戻っている）。
     *   **正直に `<none>` を記録する。** at をコピーして埋めると own の意味が壊れる。
     *
     * @return void
     */
    public static function shutdown()
    {
        $last = error_get_last();
        if ($last === null) {
            return;
        }
        $fatal = array(E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR, E_USER_ERROR);
        if (!in_array($last['type'], $fatal, true)) {
            return;
        }
        self::write(array(
            'lv' => self::levelName($last['type']),
            'ctx' => static::context(),
            'sup' => '0',
            'own' => '<none>',
            'depth' => '-1',
            'at' => self::relative((string) (@realpath($last['file']) ?: $last['file'])) . ':' . $last['line'],
            'pid' => (string) getmypid(),
            'req' => self::requestPath(),
            'msg' => self::truncate($last['message']),
        ));
    }
}

if (PhpMigrationLogger::boot()) {
    // 引数はちょうど 4 個。可変長 `...$rest` も使わない。
    set_error_handler(
        function ($errno, $errstr, $errfile, $errline) {
            return PhpMigrationLogger::handle($errno, $errstr, $errfile, $errline);
        },
        E_ALL
    );
    register_shutdown_function(array('PhpMigrationLogger', 'shutdown'));
}

endif;
