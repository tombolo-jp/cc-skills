<?php
/**
 * プローブ: 形状の無い汎用配列（`array<string, mixed>` 等）への `??` 無しの読み取り
 *
 * PHP 8.0 で Notice → **Warning に格上げ**された未定義キー読み取りのうち、
 * **level をいくら上げても既定では報告されない**類型。
 * `array|false` を `is_array()` で確定させると型は形状の無い `array` になり、
 * PHPStan は「そのキーがあるかどうか分からない」配列への読み取りを既定では黙認する。
 * `reportPossiblyNonexistentGeneralArrayOffset: true` を有効にして初めて
 * `offsetAccess.notFound`（"Offset '...' might not exist on array"）として報告される
 *（`references/detection-gates.md` §2「必須パラメータ」）。
 *
 * 実例: ACF の `get_fields()` を `references/wordpress-notes.md` の推奨どおり
 * `is_array()` で確定させたあと、`$f['period_start']` を `??` 無しで読んでいた。
 * 本番で `Warning: Undefined array key "period_start"` が出るまで静的解析は沈黙した。
 *
 * この検体は**設定の有無を測るためのもの**であり、「型の分かり具合」の軸は持たない。
 * 変種は `general` の1つだけ。設定が無い neon で走らせると検出されないのが正しい。
 */

/** @return array<string, mixed>|false */
function probe_gao_fields() { return false; }

function __probe_general_array_offset(): void
{
    $f = probe_gao_fields();
    $f = is_array($f) ? $f : [];
    // @probe-expect offsetAccess.notFound general
    $sink = $f['period_start'];
}

// `??` で守った読み取りは、設定を有効にしても報告されない（偽陽性を増やさない）。
function __probe_general_array_offset_guarded(): void
{
    $f = probe_gao_fields();
    $f = is_array($f) ? $f : [];
    $sink = $f['period_start'] ?? null;
}
