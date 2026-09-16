<?php
/**
 * プローブ: 「取得できなければ false を返す」関数の戻り値を無ガードで使う類型
 *
 * `array|false` は ACF の `get_fields()` / WordPress の `get_post_meta()` 等で頻出するが、
 * **stub からではなくこのファイル自身の PHPDoc から型を作る**（design §7.3）。
 * プロジェクトの stub 構成に依存させると、出力表がそのプロジェクトでしか意味を持たない。
 *
 * 測る identifier: オフセットアクセス系 と foreach 系 の2つ。
 */

function probe_aof_concrete(): bool { return false; }
/** @return array|false */
function probe_aof_union() { return false; }
function probe_aof_emixed(): mixed { return false; }
function probe_aof_imixed() { return false; }

// ---- オフセットアクセス ----

function __probe_offset_concrete(): void
{
    $v = probe_aof_concrete();
    // @probe-expect offsetAccess.nonOffsetAccessible concrete
    $sink = $v['key'];
}

function __probe_offset_union(): void
{
    $v = probe_aof_union();
    // @probe-expect offsetAccess.nonOffsetAccessible union
    $sink = $v['key'];
}

function __probe_offset_emixed(): void
{
    $v = probe_aof_emixed();
    // @probe-expect offsetAccess.nonOffsetAccessible emixed
    $sink = $v['key'];
}

function __probe_offset_imixed(): void
{
    $v = probe_aof_imixed();
    // @probe-expect offsetAccess.nonOffsetAccessible imixed
    $sink = $v['key'];
}

// ---- foreach ----

function __probe_foreach_concrete(): void
{
    $v = probe_aof_concrete();
    // @probe-expect foreach.nonIterable concrete
    foreach ($v as $x) { $sink = $x; }
}

function __probe_foreach_union(): void
{
    $v = probe_aof_union();
    // @probe-expect foreach.nonIterable union
    foreach ($v as $x) { $sink = $x; }
}

function __probe_foreach_emixed(): void
{
    $v = probe_aof_emixed();
    // @probe-expect foreach.nonIterable emixed
    foreach ($v as $x) { $sink = $x; }
}

function __probe_foreach_imixed(): void
{
    $v = probe_aof_imixed();
    // @probe-expect foreach.nonIterable imixed
    foreach ($v as $x) { $sink = $x; }
}
