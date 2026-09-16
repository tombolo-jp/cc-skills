<?php
/**
 * プローブ: PHP 8.0 で**削除**された API
 *
 * これらは対象バージョンで Fatal になる。互換チェッカが検出できなければ
 * 「削除 API の検出」という守備範囲に穴が開いている。
 *
 * `// @gate-expect <期待重大度> <照合トークン>` は、そのトークンを含む指摘を
 * その重大度で検出することを期待する意味。トークンは phpcs の
 * `source`（スニフ名）か `message` のいずれかに含まれていればよい。
 *
 * ★ このファイルは**解析させるためのもの**であり、実行してはならない。
 *   稼働中のドキュメントルート配下へ置かないこと（HTTP で直接実行されうる）。
 */

function gate_probe_removed_api()
{
    // @gate-expect ERROR create_function
    $f = create_function('$a', 'return $a;');

    // @gate-expect ERROR money_format
    $m = money_format('%i', 1234.56);

    // @gate-expect ERROR each
    $arr = ['a' => 1];
    $e = each($arr);

    return [$f, $m, $e];
}
