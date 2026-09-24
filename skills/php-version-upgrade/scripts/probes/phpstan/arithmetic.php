<?php
/**
 * プローブ: 非数値文字列（`''` を含む）との算術演算
 *
 * PHP 8.0 で **Warning → TypeError（Fatal）に格上げ**された類型
 *（`Unsupported operand types: string - int`）。7.4 では Warning と `-1` 等で処理が続いていた。
 * 先頭が数値の文字列（`'5abc'`）は 8.0 以降も Warning のままで、TypeError にはならない。
 *
 * WordPress では `get_post_meta(..., true)` がメタ未登録時に返す `''` を
 * そのまま計算する形で現れる。
 *
 * この identifier は既定のホワイトリスト（`scripts/php8-identifiers.txt`）から漏れていた。
 * ホワイトリスト自体が allowlist であり漏れることの、`property.notFound` に続く2例目。
 */

function probe_ar_concrete(): string { return ''; }
/** @return string|int */
function probe_ar_union() { return ''; }
function probe_ar_emixed(): mixed { return ''; }
function probe_ar_imixed() { return ''; }

function __probe_arithmetic_concrete(): void
{
    $v = probe_ar_concrete();
    // @probe-expect binaryOp.invalid concrete
    $sink = $v - 1;
}

function __probe_arithmetic_union(): void
{
    $v = probe_ar_union();
    // @probe-expect binaryOp.invalid union
    $sink = $v - 1;
}

function __probe_arithmetic_emixed(): void
{
    $v = probe_ar_emixed();
    // @probe-expect binaryOp.invalid emixed
    $sink = $v - 1;
}

function __probe_arithmetic_imixed(): void
{
    $v = probe_ar_imixed();
    // @probe-expect binaryOp.invalid imixed
    $sink = $v - 1;
}

// 複合代入（`-=` 等）は別 identifier になる。
function __probe_arithmetic_assign(): void
{
    $v = probe_ar_concrete();
    // @probe-expect assignOp.invalid assign
    $v -= 1;
}
