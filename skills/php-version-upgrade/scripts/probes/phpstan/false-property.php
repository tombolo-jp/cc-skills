<?php
/**
 * プローブ: 「対象が無ければ false / null を返す」関数の戻り値へ無ガードでプロパティ参照
 *
 * WordPress の `get_user_by()` / `get_post()` が該当する類型だが、
 * 型はこのファイル自身の宣言から作る（stub 非依存）。
 * PHP 8.0 で「false に対するプロパティ読み取り」は Warning に格上げされている。
 */

class ProbeUser
{
    public int $ID = 0;
}

function probe_user_concrete(): bool { return false; }
/** @return ProbeUser|false */
function probe_user_union() { return false; }
function probe_user_emixed(): mixed { return false; }
function probe_user_imixed() { return false; }

function __probe_property_concrete(): void
{
    $u = probe_user_concrete();
    // @probe-expect property.nonObject concrete
    $sink = $u->ID;
}

function __probe_property_union(): void
{
    $u = probe_user_union();
    // @probe-expect property.nonObject union
    $sink = $u->ID;
}

function __probe_property_emixed(): void
{
    $u = probe_user_emixed();
    // @probe-expect property.nonObject emixed
    $sink = $u->ID;
}

function __probe_property_imixed(): void
{
    $u = probe_user_imixed();
    // @probe-expect property.nonObject imixed
    $sink = $u->ID;
}
