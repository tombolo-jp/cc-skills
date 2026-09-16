<?php
/**
 * プローブ: PHP 8.1 / 8.2 で**非推奨**になった API
 *
 * 非推奨は実行時に E_DEPRECATED を出すだけで動作は続くため、
 * 静的に拾えないと**移行完了後もログを汚し続け、次のメジャーで壊れる**。
 *
 * ★ このファイルは解析させるためのものであり、実行してはならない。
 */

function gate_probe_deprecated_api()
{
    // @gate-expect ERROR FILTER_SANITIZE_STRING
    $s = filter_var('x', FILTER_SANITIZE_STRING);

    // @gate-expect ERROR strftime
    $t = strftime('%Y-%m-%d');

    // @gate-expect ERROR utf8_encode
    $u = utf8_encode('x');

    // @gate-expect ERROR utf8_decode
    $d = utf8_decode('x');

    return [$s, $t, $u, $d];
}
