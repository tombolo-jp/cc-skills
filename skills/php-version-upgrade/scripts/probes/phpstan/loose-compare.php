<?php
/**
 * プローブ: 非厳密比較（`==`）が常に真／常に偽になる類型
 *
 * PHP 8.0 の文字列⇔数値比較のセマンティクス変更（`0 == "abc"` が true → false）に
 * 対応する identifier だが、**この identifier で拾えるのは両辺の型が静的に確定する場合だけ**である。
 *
 * **重要**: DB・外部入力由来の `mixed` に対しては原理的に拾えない。
 * `in_array()` の第3引数なし呼び出しは PHPStan では検出できないため、
 * この検体には含めない（`references/breaking-changes.md` §7 が引き受ける）。
 * プローブに書ける類型は**測定できるものに限る**（design §7.3）。
 */

function probe_lc_int(): int { return 0; }
/** @return int|string */
function probe_lc_union() { return 0; }
function probe_lc_emixed(): mixed { return 0; }
function probe_lc_imixed() { return 0; }

function __probe_equal_concrete(): void
{
    $v = probe_lc_int();
    // @probe-expect equal.alwaysFalse concrete
    if ($v == 'abc') { echo 'hit'; }
}

function __probe_equal_union(): void
{
    $v = probe_lc_union();
    // 実測: どの level でも検出されない。両辺の型が静的に確定しないため（表は —）
    if ($v == 'abc') { echo 'hit'; }
}

function __probe_equal_emixed(): void
{
    $v = probe_lc_emixed();
    // 実測: どの level でも検出されない。両辺の型が静的に確定しないため（表は —）
    if ($v == 'abc') { echo 'hit'; }
}

function __probe_equal_imixed(): void
{
    $v = probe_lc_imixed();
    // 実測: どの level でも検出されない。両辺の型が静的に確定しないため（表は —）
    if ($v == 'abc') { echo 'hit'; }
}
