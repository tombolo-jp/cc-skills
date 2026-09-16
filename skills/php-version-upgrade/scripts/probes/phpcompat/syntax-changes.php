<?php
/**
 * プローブ: 構文レベルの変更
 *
 * 構文の非推奨・削除は、静的に拾えなければ**対象バージョンのバイナリでの `php -l`**
 * でしか捕まらない。互換チェッカがここを検出できるかどうかで、
 * 「`php -l` を別途回す必要があるか」が決まる。
 *
 * ★ このファイルは解析させるためのものであり、実行してはならない。
 */

function gate_probe_syntax_changes()
{
    $var = 'x';

    // ${var} 形式の文字列補間は PHP 8.2 で非推奨。
    // @gate-expect ERROR StringInterpolation
    $a = "value: ${var}";

    // ${expr} 形式も同様。
    // @gate-expect ERROR StringInterpolation
    $b = "value: ${arr['k']}";

    return [$a, $b];
}
