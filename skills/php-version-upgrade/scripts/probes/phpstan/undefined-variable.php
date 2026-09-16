<?php
/**
 * プローブ: 未定義変数の参照
 *
 * PHP 8.0 で E_NOTICE → **E_WARNING に格上げ**された類型。
 * 7.x の既定 `error_reporting` は E_NOTICE を含まないため、移行するまで表面化しない。
 *
 * この identifier に「型の分かり具合」の軸は無い（変数が存在するか否かの問題であり、
 * 型推論の深さに依存しない）。したがって変種は `concrete` の1つだけを持つ。
 */

function __probe_variable_undefined(): void
{
    // @probe-expect variable.undefined concrete
    $sink = $probe_never_assigned;
}

function __probe_variable_undefined_branch(): void
{
    // 条件分岐の中だけで代入され、分岐の外で無条件参照される最頻出パターン。
    if (PHP_INT_SIZE === 4) {
        $probe_maybe = 'x';
    }
    // @probe-expect variable.undefined branch
    $sink = $probe_maybe;
}
