<?php
/**
 * プローブ: 宣言されていないプロパティへのアクセス
 *
 * 読み取りは PHP 8.0 で Notice → **Warning に格上げ**。
 * 書き込みは PHP 8.2 で **Deprecated**（動的プロパティの作成）。
 *
 * design §0 M15 の当事者。本プロジェクトではこの identifier が
 * 4系統のホワイトリストから漏れ、1件が未仕分けのまま残っていた。
 * ホワイトリスト自体が allowlist であり漏れることの実証例。
 *
 * 「型の分かり具合」の軸は無いため変種は `concrete` の1つだけ。
 */

class ProbeDeclared
{
    public int $declared = 0;
}

function __probe_property_not_found(): void
{
    $o = new ProbeDeclared();
    // @probe-expect property.notFound concrete
    $sink = $o->undeclared;
}

function __probe_property_dynamic_write(): void
{
    $o = new ProbeDeclared();
    // @probe-expect property.notFound write
    $o->undeclaredWrite = 1;
}
