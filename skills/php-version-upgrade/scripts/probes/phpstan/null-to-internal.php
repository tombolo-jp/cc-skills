<?php
/**
 * プローブ: null を内部関数の非 nullable 引数へ渡す類型
 *
 * PHP 8.1 で **Deprecated**（`Passing null to parameter #1 ($string) of type string is deprecated`）。
 * 件数が最も多くなりやすい identifier であり、`mixed given` のノイズも同居する。
 * ホワイトリストへ入れる場合はメッセージによる二次フィルタが要ることがある（design §7.2）。
 */

function probe_nti_null(): ?string { return null; }
/** @return string|null */
function probe_nti_union() { return null; }
function probe_nti_emixed(): mixed { return null; }
function probe_nti_imixed() { return null; }

function __probe_argument_concrete(): void
{
    $v = null;
    // @probe-expect argument.type concrete
    $sink = strlen($v);
}

function __probe_argument_union(): void
{
    $v = probe_nti_union();
    // @probe-expect argument.type union
    $sink = strlen($v);
}

function __probe_argument_emixed(): void
{
    $v = probe_nti_emixed();
    // @probe-expect argument.type emixed
    $sink = strlen($v);
}

function __probe_argument_imixed(): void
{
    $v = probe_nti_imixed();
    // @probe-expect argument.type imixed
    $sink = strlen($v);
}
