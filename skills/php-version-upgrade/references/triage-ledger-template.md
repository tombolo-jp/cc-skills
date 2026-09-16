# 仕分け台帳の空雛形

コピーして使う。スキーマの定義と規約は `references/triage-ledger.md` を参照する。

**フェンス（`<!-- ledger:meta v1 -->` / `<!-- ledger:rows v1 -->`）を消さないこと。** 機械判定はフェンス内のみを読む。見出しや前後の説明文は自由に書き換えてよい。

---

## 静的解析の仕分け台帳（`kind: phpstan-triage`）

```markdown
# PHPStan 仕分け台帳

行番号は生成時点のものである。**突合キーは `path` + `identifier` + `message` であり、行番号は含まない。**

<!-- ledger:meta v1 -->
| キー | 値 |
|---|---|
| kind | phpstan-triage |
| tool | phpstan <x.y.z> |
| level | <n> |
| phpVersion | <80300 等> |
| identifiers | <ホワイトリストファイルのパス> |
| stubs | <scanFiles に入れた stub> |
| paths | <解析対象パス> |
| judged_at | <YYYY-MM-DD> |
<!-- /ledger:meta -->

<!-- ledger:rows v1 -->
| 状態 | path | identifier | message | count | 根拠種別 | 判定根拠 | 判定関与 | 外部入力起点 | 参考行 |
|---|---|---|---|---|---|---|---|---|---|
| 未判定 | path/to/file.php | offsetAccess.nonOffsetAccessible | Cannot access offset 'k' on array\|false. | 1 | — |  | N | N | 12 |
<!-- /ledger:rows -->
```

- `状態`: `未判定` / `対応済` / `偽陽性` / `保留`
- `根拠種別`: `到達不能` / `実測` / `仕様` / `—`
- `判定根拠`: **20 文字以上必須**。空・短すぎる行は状態によらず未仕分け扱い（`偽陽性` なら書式エラー）
- `message` 内の `|` は `\|` へエスケープする

---

## 棚卸し台帳（`kind: grep-inventory`）

```markdown
# <対象パターン> 棚卸し台帳

**本台帳の対象は <対象> のみ。** <対象外のもの> は別タスクとする。

<!-- ledger:meta v1 -->
| キー | 値 |
|---|---|
| kind | grep-inventory |
| pattern | <実行した正規表現> |
| paths | <列挙対象> |
| judged_at | <YYYY-MM-DD> |
<!-- /ledger:meta -->

<!-- ledger:rows v1 -->
| 状態 | path | 連番 | 正規化断片 | 根拠種別 | 判定根拠 | 対応 | 確認方法 | 参考行 |
|---|---|---|---|---|---|---|---|---|
| 未判定 | path/to/file.php | 1 | in_array($k, $list) | — |  | — |  | 42 |
<!-- /ledger:rows -->
```

- `状態`: `未判定` / `安全` / `条件付き` / `危険` / `別件`（「偽陽性」は使わない）
- **`安全` にも必ず `判定根拠` を埋める**（ルール名でよい）

---

## 対象ファイル台帳（`kind: scope`）

```markdown
# 対象ファイル台帳（denylist）

<!-- ledger:meta v1 -->
| キー | 値 |
|---|---|
| kind | scope |
| paths | <target-paths> |
| judged_at | <YYYY-MM-DD> |
<!-- /ledger:meta -->

<!-- ledger:rows v1 -->
| 状態 | path | 区分 | 除外理由 |
|---|---|---|---|
| 対応済 | path/to/file.php | 対象 | — |
<!-- /ledger:rows -->
```

- ゲート: `git ls-files '<paths>/*.php'` の**全件 == 行数**
- **見積もり時間の列を作らない**（行を減らす動機が生まれる）

---

## フィードバック突合台帳（`kind: feedback`）

```markdown
# 移行後フィードバック突合

**対象3種それぞれについて、0 件でも「0 件だった」行を残す。** 行が1つも無い台帳は「未実施」と区別できない。

<!-- ledger:meta v1 -->
| キー | 値 |
|---|---|
| kind | feedback |
| period | <YYYY-MM-DD>〜<YYYY-MM-DD> |
| judged_at | <YYYY-MM-DD> |
<!-- /ledger:meta -->

<!-- ledger:rows v1 -->
| 状態 | source | evidence | location | category | detectable_by | why_missed | verified_by | skill_action | applied |
|---|---|---|---|---|---|---|---|---|---|
| 未判定 | 実行時ログ | 0 件 | — | — | — | — | — | — | — |
<!-- /ledger:rows -->
```

- `why_missed`: `W1-設定値誤り` / `W2-バージョン要件未規定` / `W3-守備範囲の誤認` / `W4-原則の非強制` / `W5-突合方式の欠落` / `W6-手段の不在` / `W7-ツールの原理的限界` / `W8-フェーズの未実施`
- **W1〜W6 のとき `skill_action` に `対応不要` と書いてはならない**
