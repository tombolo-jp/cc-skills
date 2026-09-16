<?php
/**
 * プローブ: 存在しない配列キーへのアクセス
 *
 * PHP 8.0 で Notice → **Warning に格上げ**された類型。
 * 実データを流して初めて表面化することが多い
 *（`$data[$key]['x']` で外側キーが特定のレコードでだけ欠けるパターン）。
 */

/** @return array{a: int} */
function probe_shape_concrete() { return ['a' => 1]; }
/** @return array{a: int}|array{b: int} */
function probe_shape_union() { return ['a' => 1]; }
function probe_shape_emixed(): mixed { return ['a' => 1]; }
function probe_shape_imixed() { return ['a' => 1]; }

function __probe_shape_concrete(): void
{
    $v = probe_shape_concrete();
    // @probe-expect offsetAccess.notFound concrete
    $sink = $v['missing'];
}

function __probe_shape_union(): void
{
    $v = probe_shape_union();
    // @probe-expect offsetAccess.notFound union
    $sink = $v['missing'];
}

function __probe_shape_emixed(): void
{
    $v = probe_shape_emixed();
    // 実測: mixed に対しては offsetAccess.notFound ではなく nonOffsetAccessible が出る（表は —）
    $sink = $v['missing'];
}

function __probe_shape_imixed(): void
{
    $v = probe_shape_imixed();
    // 実測: 同上。「キーが無い」は形状が分かる型にしか成立しない（表は —）
    $sink = $v['missing'];
}

// 入れ子配列。外側キーが欠けると「未定義キー ＋ null offset」の二段になる。
function __probe_shape_nested(): void
{
    $v = probe_shape_concrete();
    // @probe-expect offsetAccess.notFound nested
    $sink = $v['missing']['inner'];
}
