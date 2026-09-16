<?php
/**
 * プローブ: Array to string conversion
 *
 * PHP 8.0 で Notice → **Warning に格上げ**された類型。
 * 出力へ配列がそのまま混入するため、CSV / JSON 生成経路では**ファイル破損に直結**する。
 */

function probe_ats_concrete(): array { return ['a']; }
/** @return array|string */
function probe_ats_union() { return ['a']; }
function probe_ats_emixed(): mixed { return ['a']; }
function probe_ats_imixed() { return ['a']; }

function __probe_echo_concrete(): void
{
    $v = probe_ats_concrete();
    // @probe-expect echo.nonString concrete
    echo $v;
}

function __probe_echo_union(): void
{
    $v = probe_ats_union();
    // @probe-expect echo.nonString union
    echo $v;
}

function __probe_echo_emixed(): void
{
    $v = probe_ats_emixed();
    // @probe-expect echo.nonString emixed
    echo $v;
}

function __probe_echo_imixed(): void
{
    $v = probe_ats_imixed();
    // @probe-expect echo.nonString imixed
    echo $v;
}

// 文字列補間内での配列参照。`echo` とは別 identifier になる。
function __probe_encapsed_concrete(): void
{
    $v = probe_ats_concrete();
    // @probe-expect encapsedStringPart.nonString encapsed
    echo "value: {$v}";
}
