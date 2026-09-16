<?php
/**
 * プローブ: オフセットの**型**が配列添字として妥当でない類型
 *
 * design §6.2 でこの identifier だけ下限 level が空欄（要実測）として残されていた。
 * **実測前に数値を書けば、本タスクが是正しようとしている誤記と同型になる。**
 * したがって検体を先に置き、`probe-phpstan-levels.sh` の出力で表を埋める。
 *
 * `is_array()` ガードを足して「オフセットアクセス不可」を解消した結果、
 * 今度は「オフセットの型が不正」へ入れ替わる（総件数は変わらない）という
 * design §8.3 の実例そのものの類型でもある。
 */

/** @return array<string, int> */
function probe_io_map() { return ['a' => 1]; }
function probe_io_offset_concrete(): array { return []; }
/** @return array|string */
function probe_io_offset_union() { return []; }
function probe_io_offset_emixed(): mixed { return []; }
function probe_io_offset_imixed() { return []; }

function __probe_invalid_offset_concrete(): void
{
    $map = probe_io_map();
    $k = probe_io_offset_concrete();
    // @probe-expect offsetAccess.invalidOffset concrete
    $sink = $map[$k];
}

function __probe_invalid_offset_union(): void
{
    $map = probe_io_map();
    $k = probe_io_offset_union();
    // @probe-expect offsetAccess.invalidOffset union
    $sink = $map[$k];
}

function __probe_invalid_offset_emixed(): void
{
    $map = probe_io_map();
    $k = probe_io_offset_emixed();
    // @probe-expect offsetAccess.invalidOffset emixed
    $sink = $map[$k];
}

function __probe_invalid_offset_imixed(): void
{
    $map = probe_io_map();
    $k = probe_io_offset_imixed();
    // @probe-expect offsetAccess.invalidOffset imixed
    $sink = $map[$k];
}

// float 添字（8.1 で Deprecated: Implicit conversion from float to int）
function __probe_invalid_offset_float(): void
{
    $map = probe_io_map();
    // @probe-expect offsetAccess.invalidOffset float
    $sink = $map[1.5];
}
