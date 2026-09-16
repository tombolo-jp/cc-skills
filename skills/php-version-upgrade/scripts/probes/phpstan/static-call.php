<?php
/**
 * プローブ: 静的コンテキストからの非 static メソッド呼び出し
 *
 * PHP 8.0 で **Fatal** 化した類型（7.x は Deprecated で動作していた）。
 * `$this` を使っていなくても Fatal になる。
 * クラスを名前空間代わりに `self::` 多用する WordPress 系コードで発生しやすい。
 *
 * 「型の分かり具合」の軸は無いため変種は `concrete` の1つだけ。
 */

class ProbeStaticCall
{
    public function instanceMethod(): string
    {
        return 'x';
    }

    public static function staticEntry(): string
    {
        // @probe-expect method.staticCall concrete
        return self::instanceMethod();
    }
}
