# Rector推奨設定と「やりすぎ」回避

## LevelSetListの罠

`Rector\Set\ValueObject\LevelSetList::UP_TO_PHP_83` のような「バージョン上限指定」セットは、**そのバージョンで初めて使える構文への機械的なアップグレード**まで実行する。移行元バージョンとの並走期間がある場合、これが本番障害の原因になり得る。

```php
// 危険な例: 7.4/8.3並走時間帯があるのに UP_TO_PHP_83 をそのまま使う
return RectorConfig::configure()
    ->withSets([
        LevelSetList::UP_TO_PHP_83, // 8.1構文（第一級callable等）まで適用してしまう
    ]);
```

### 対処方針

**方針A（推奨・再実行しない）**: 一度 `LevelSetList::UP_TO_PHP_83` 等を実行してしまった後は、Rectorを再実行せず、`--keep-compat` に違反する差分だけを正規表現等でピンポイント置換する。理由: Rector再実行は無関係な差分も動かしてしまい、既にレビュー済みの差分の再検証が必要になる。置換の網羅性は「Rectorに任せる」のではなく、PHPCompatibilityのERROR 0件ゲートで機械的に担保する。

**方針B（次回以降の実行に備える・再発防止）**: 該当ルールを `withSkip()` で除外し、以後のRector実行では同じ問題が起きないようにする。

```php
use Rector\Php81\Rector\Array_\ArrayToFirstClassCallableRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnNeverTypeRector;
// 必要に応じて追加:
// use Rector\Php81\Rector\Property\ReadOnlyPropertyRector;
// use Rector\Php81\Rector\ClassConst\FinalizePublicClassConstantRector;
// use Rector\Php80\Rector\Class_\ClassPropertyAssignToConstructorPromotionRector;

return RectorConfig::configure()
    ->withSets([
        LevelSetList::UP_TO_PHP_83,
    ])
    ->withSkip([
        // ...既存のパス除外...

        // 完全移行でも除外を推奨（下記）: コールバックの同一性を壊す
        ArrayToFirstClassCallableRector::class,
        // 以下は下位バージョンでのパースエラー回避が目的＝--keep-compat 指定時のみ必要
        ReturnNeverTypeRector::class,
    ]);
```

**`ArrayToFirstClassCallableRector` の除外は、完全移行（`--keep-compat` 未指定）でも推奨する**。`[$obj, 'method']`→`$obj->method(...)` 変換は「コールバックの同一性」に依存する箇所——WordPressの `add_action`/`add_filter` で登録し `remove_action`/`remove_filter` で解除する等——を壊しうるためで、これは下位互換の問題とは別に発生する。「完全移行だから安全」ではない（実機検証で確認済み）。

一方 `ReturnNeverTypeRector`/`ReadOnlyPropertyRector`/`enum`/コンストラクタプロパティ昇格 系のルール除外は、**下位バージョンでのパースエラー回避が目的なので `--keep-compat` 指定時のみ**必要。完全移行ではこれらの新構文を許容してよい。

## `--keep-compat` 指定時に確認すべきRectorルール一覧（PHP 8.0/8.1系）

| ルール | 導入する構文 | 8.0/8.1未満でのパース結果 |
|---|---|---|
| `ArrayToFirstClassCallableRector` | 第一級callable `(...)` | Parse error |
| `ReturnNeverTypeRector` | `never` 戻り値型 | Parse error |
| `ReadOnlyPropertyRector` | `readonly` プロパティ | Parse error |
| `ClassPropertyAssignToConstructorPromotionRector` | コンストラクタプロパティ昇格 | Parse error |
| `Php80\...\ChangeSwitchToMatchRector` | `match` 式 | Parse error |
| enum関連ルール一式 | `enum` | Parse error |

導入するRectorのバージョンによってクラス名・パッケージ構成が変わるため、実際に導入したバージョンで `vendor/rector/rector/rules/` 配下を検索し、正確なクラス名を確認すること（`find vendor/rector -iname "*FirstClassCallable*"` 等）。

## 除外パス設定の一致

静的解析ツール（PHPStan/PHPCompatibility）の除外パス設定は、Rectorの `withSkip()` のパス除外設定と**完全一致**させる。不一致があると、「Rectorは触っていないのに静的解析はエラーを出す（またはその逆）」という混乱が生じる。vendor・自動生成ディレクトリ・ビルド成果物ディレクトリは通常両方から除外する。

## キャッシュディレクトリ

Rector・PHPStan・PHPCS はいずれもキャッシュディレクトリを持つ（`.rector-cache`、`.phpstan-cache` 等）。これらはリポジトリの `.gitignore` に追加し、コミット対象から除外する。
