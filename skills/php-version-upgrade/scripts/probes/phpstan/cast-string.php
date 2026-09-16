<?php
/**
 * プローブ: array → string キャスト
 *
 * 型の分かり具合を4変種（確定型 / union / explicit mixed / implicit mixed）で用意し、
 * 同一 identifier の下限 level が型の形で動くこと（design §0 M2）を測る。
 *
 * 規約:
 *   - 全コードを未呼び出し関数の中に置く。PHPStan は未呼び出し関数も完全に解析するため
 *     検出には影響せず、万一 include されても副作用が無い。
 *   - 型はこのファイル自身の宣言から作る。プロジェクトの stub に依存させない。
 *   - `// @probe-expect <identifier> <variant>` は**直後の1行**に対する期待。
 */

function probe_cast_string_concrete(): array { return ['a']; }
/** @return array|string */
function probe_cast_string_union() { return ['a']; }
function probe_cast_string_emixed(): mixed { return ['a']; }
function probe_cast_string_imixed() { return ['a']; }

function __probe_cast_string_concrete(): void
{
    $v = probe_cast_string_concrete();
    // @probe-expect cast.string concrete
    $sink = (string) $v;
}

function __probe_cast_string_union(): void
{
    $v = probe_cast_string_union();
    // @probe-expect cast.string union
    $sink = (string) $v;
}

function __probe_cast_string_emixed(): void
{
    $v = probe_cast_string_emixed();
    // @probe-expect cast.string emixed
    $sink = (string) $v;
}

function __probe_cast_string_imixed(): void
{
    $v = probe_cast_string_imixed();
    // @probe-expect cast.string imixed
    $sink = (string) $v;
}
