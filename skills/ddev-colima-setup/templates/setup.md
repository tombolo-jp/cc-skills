# セットアップ手順 — DDEV + Colima 開発環境

clone 直後に開発環境を立ち上げるための手順。対象は macOS（Apple Silicon）。

- DDEV プロジェクト名: `__PROJECT_NAME__`
- Colima プロファイル: `ddev`（**ホスト共通の共有 VM**。全 DDEV プロジェクトで 1 台を共用する）
- 開発 URL: `https://__FQDN__`
- Mailpit URL: `https://__FQDN__:__MAILPIT_HTTPS_PORT__`
- PHP `__PHP_VERSION__` / MariaDB `__MARIADB_VERSION__`

> **共有 VM であることの意味**: macOS の 443 は 1 つしかなく、それを占有する DDEV ルータも
> 1 Docker ホストにつき 1 つ。ポートなしのクリーン HTTPS URL を複数プロジェクトで同時に
> 成立させるには、全プロジェクトが同じ Colima VM に載るしかない。
> 結果として **VM の停止・ディスク枯渇は全プロジェクトに波及する**。停止操作の範囲には注意すること。

> 既に旧方式（プロジェクトごとの専用 Colima プロファイル）で構築済みの環境がある場合は、
> 本手順ではなく **`migrate.md`（同じディレクトリ）の移行手順**から始めること。

---

## 1. ツール導入

```bash
# Xcode CLT と Homebrew（未導入なら）
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# リポジトリ取得（<repo-url> は自分のリポジトリに置換）
git clone <repo-url> && cd $(basename <repo-url> .git)

# 依存をまとめて導入（colima / docker CLI / ddev / mkcert / nss）
brew bundle --file=./Brewfile

# Homebrew 版 docker プラグインを CLI から発見できるよう配線
# （これが無いと `ddev start` が "buildx ... not found" で止まる）
mkdir -p ~/.docker/cli-plugins
ln -sfn "$(brew --prefix docker-buildx)/bin/docker-buildx"   ~/.docker/cli-plugins/docker-buildx
ln -sfn "$(brew --prefix docker-compose)/bin/docker-compose" ~/.docker/cli-plugins/docker-compose

# ローカル HTTPS の信頼 CA を登録（sudo 要求あり）
mkcert -install
```

**確認**: `colima --version` / `docker --version` / `ddev --version` / `docker buildx version` がすべて応答すること。

---

## 2. 環境を起動

```bash
# 共有 Colima VM 起動 + docker context 切替
./scripts/colima-start.sh

# DDEV 初回起動（web/db image を pull。/etc/hosts 登録で一度 sudo を求める）
ddev start
```

- **共有 VM がまだ無い場合のみ** VM を作成する（5〜10 分）。
- **他プロジェクトが既に起動している場合は VM 作成も再起動も起きない**。
  「既に起動中」と表示されて素通りするのが正常な状態である。
- 既存 VM のリソースが `.colima/ddev.yaml` の値と食い違う場合は警告が出る。
  VM は作り直さない（全プロジェクトの DB データが消えるため）。揃えたいときは
  § 共有 VM のリソースを変更する に従うこと。

**確認**: `ddev describe` の URL が `https://__FQDN__` になっていること。

---

## 3. 設定保護を有効化（WordPress + DDEV 必須手順）

初回 `ddev start` で DDEV が `wp-config-ddev.php` を生成する。挙動は `wp-config.php` の
状態で 2 通り分岐するので、自分のケースを選んで進めること。

### ケース A: クリーン WP（`wp-config.php` がまだ無い / DDEV 管理を許可している）

DDEV が `wp-config.php` 末尾に `require_once __DIR__ . '/wp-config-ddev.php';` を
**自動挿入する**。確認のみで OK。

```bash
ls -la wp-config-ddev.php
tail -3 wp-config.php          # require_once ... '/wp-config-ddev.php'; が入っていること
```

### ケース B: user-managed `wp-config.php`（既存サイトの移行）

`ddev start` のログに `An existing user-managed wp-config.php file has been detected!`
が出た場合はこちら。DDEV は **require を自動追加しない**。さらに既存の `define('DB_NAME', ...)`
等が先勝ちすると、DDEV 側の `defined()||define()` が no-op になり DB 接続できない。

以下を `wp-config.php` に手動適用する:

```php
// (a) ファイル先頭近く、DB 定義より前に挿入
if ( file_exists( __DIR__ . '/wp-config-ddev.php' ) ) {
  require_once __DIR__ . '/wp-config-ddev.php';
}

// (b) 既存の define を defined()||define() パターンに置き換える
defined( 'DB_NAME' )     || define( 'DB_NAME', 'local' );      // Local 用 fallback
defined( 'DB_USER' )     || define( 'DB_USER', 'root' );
defined( 'DB_PASSWORD' ) || define( 'DB_PASSWORD', 'root' );
defined( 'DB_HOST' )     || define( 'DB_HOST', 'localhost' );
defined( 'DB_CHARSET' )  || define( 'DB_CHARSET', 'utf8' );
defined( 'DB_COLLATE' )  || define( 'DB_COLLATE', '' );
```

これで Local（IS_DDEV_PROJECT 未設定）/ DDEV（IS_DDEV_PROJECT=true で wp-config-ddev.php
が DB_* を先に定義）両方で動く。`wp-config-ddev.php` は IS_DDEV_PROJECT が未設定なら
早期 `return` するため Local では no-op。

### 共通: 設定保護を有効化して反映

```bash
# .ddev/config.yaml を編集: disable_settings_management: false → true
#   （独自定数を保護。以後 DDEV は wp-config.php を編集しない）
ddev restart
```

> 既存の DB と `wp-config.php`（独自の暗号鍵など）を別環境から受領する運用の場合は、
> 受領した `wp-config.php` を配置してから本ステップを行う。
> 秘密情報を含む `wp-config.php` はチャット等で共有せず、安全な経路で受け渡すこと。

---

## 4. DB を投入（任意）

既存 DB のダンプがある場合のみ実施。新規構築なら空 DB のままで構わない。

```bash
# 4.1 投入用の I/O 高速化設定を一時的に有効化
mv .ddev/mysql/zz-import.cnf.disabled .ddev/mysql/zz-import.cnf
ddev restart

# 4.2 ダンプを投入（gz/bz2/xz/zip 自動展開）
time ddev import-db --file="$HOME/Downloads/dump.sql.gz"

# 4.3 ★戻し忘れ厳禁★ I/O 設定を無効化に戻す
mv .ddev/mysql/zz-import.cnf .ddev/mysql/zz-import.cnf.disabled
ddev restart

# 4.4 URL を本開発 URL へ一括置換（<旧URL> はダンプ元のサイト URL）
ddev wp search-replace '<旧URL>' 'https://__FQDN__' \
  --all-tables-with-prefix --skip-columns=guid --report-changed-only
ddev wp cache flush
ddev wp option get home      # "https://__FQDN__" を確認

# 4.5 初回 snapshot を作成（以後はここへ即復元できる）
ddev snapshot --name="initial_$(date +%Y%m%d-%H%M%S)"
```

---

## 5. 動作確認

```bash
open https://__FQDN__
```

- [ ] サイトが表示され、証明書警告が出ない
- [ ] WP 管理画面（`/wp-admin`）にログインできる
- [ ] （DB 投入時）想定どおりのコンテンツが表示される
- [ ] Mailpit（`https://__FQDN__:__MAILPIT_HTTPS_PORT__`）が開く

---

## 完了後の日常運用

```bash
./scripts/dev-up.sh      # 一括起動: 共有 VM → ddev start → ブラウザ
ddev ssh                 # web コンテナへ
ddev wp <subcommand>     # WP-CLI
ddev mysql               # DB シェル
./scripts/dev-down.sh    # このプロジェクトのみ停止（他プロジェクト・VM は動いたまま）
./scripts/colima-stop.sh # 共有 VM ごと停止（★全プロジェクトが停止する★）
```

**停止操作は 2 段ある。取り違えると他プロジェクトの作業を止めてしまう。**

| やりたいこと | コマンド | 範囲 |
|---|---|---|
| このプロジェクトを閉じる（日常） | `./scripts/dev-down.sh` | このプロジェクトのコンテナのみ |
| マシンを落とす・再起動する前 | `./scripts/colima-stop.sh` | 全プロジェクト + ルータ + 共有 VM |

### Mailpit（送信メールの確認）

このプロジェクトの Mailpit は `https://__FQDN__:__MAILPIT_HTTPS_PORT__`。
`./scripts/dev-up.sh` が実割当の URL を取得して自動で開く。

ルータの 80/443 は全プロジェクト共通だが、**Mailpit はプロジェクトごとにホストの
ポートを占有する**ため、値がプロジェクトごとに異なる。生成時に既知プロジェクトの
使用中ポートを避けて HTTPS 起点 `8026` から 2 刻みで採番している
（`8026` → `8028` → `8030` …。HTTP はその 1 つ下）。

新しいプロジェクトを追加して `ddev start` がポート衝突で失敗する場合は、
`.ddev/config.yaml` の `mailpit_http_port` / `mailpit_https_port` を空き番号へ変更して
`ddev restart` する。

### 共有 VM のリソースを変更する

**リポジトリの `.colima/ddev.yaml` を編集しただけでは VM に反映されない。**
colima が起動時に読むのは colima 自身の保存済み設定（`~/.colima/ddev/colima.yaml`）であり、
リポジトリ内のファイルではない。リポジトリ側は「**まだ VM が無いときに** `colima-start.sh` が
CLI フラグへ展開する元」と「差異警告の期待値」という 2 つの役割しか持たない。

反映には colima 側へ値を渡す必要がある。

```bash
# 1. 全プロジェクトと VM を停止（★他プロジェクトも止まる。作業者に確認すること★）
./scripts/colima-stop.sh

# 2. 新しい値を指定して起動し直す（colima が保存済み設定を更新する）
#    ※ vmType / mountType / arch は VM 作成後は変更できない（変えると VM の作り直しになる）
colima start --profile ddev --cpu 4 --memory 12 --disk 80
docker context use colima-ddev

# 3. リポジトリの .colima/ddev.yaml も同じ値へ書き換えてコミットする
#    （次に環境を作る人が同じ VM を得るため。差異警告もこの値と比較される）
```

`colima start --profile ddev --edit` で保存済み設定をエディタで開いて編集する方法もある。
どちらの場合も手順 3 は必要。

- `cpu` / `memory` は増減とも可能。
- **`disk` は拡張のみ可能で、縮小できない。** 小さくしたい場合は VM の作り直し
  （= 全プロジェクトの DB を退避してから再作成）が必要になる。
- 変更後に `./scripts/colima-start.sh` を実行すると、実リソースと `.colima/ddev.yaml` の
  差異が警告として出る。**警告が消えていれば、VM とリポジトリの両方が揃っている。**
  手順 2 だけ実施して 3 を忘れると警告が出続ける（VM 側は正しい）。
- `.colima/ddev.yaml` は全プロジェクトで同一内容。1 つのリポジトリだけ書き換えても
  他リポジトリの値とずれるだけなので、恒久的な変更は全リポジトリへ反映すること。

### プロファイリングについて

xhgui は使わない。`.ddev/config.yaml` で `xhprof_mode: prof` を指定しており、
既定の xhgui モード（プロファイル結果を MariaDB へ無制限に蓄積する）は無効化してある。
プロファイルが必要なときだけ `ddev xhprof on` を使い、結果はファイルとして出力される。

### VM ディスク使用量の定期確認（推奨）

共有 VM ではディスク枯渇が**全プロジェクトを同時に停止させる**。月に一度など、
定期的に使用量を確認する運用にすること。

```bash
colima ssh --profile ddev -- df -h /mnt/lima-colima-ddev
du -sh ~/.colima/_lima/_disks/colima-ddev/
```

使用率が 80% を超えたら § ディスク枯渇からの復旧 の `fstrim` まで実施しておく。

---

## トラブルシュート

| 症状 | 対処 |
|---|---|
| `ddev start` が `buildx ... not found` で停止 | §1 の docker-buildx シンボリックリンクを実施 |
| web コンテナが起動直後に exit（`docker logs ddev-__PROJECT_NAME__-web` に `No space left on device`） | 共有 VM のディスク枯渇。**全プロジェクトが影響を受ける**。§ ディスク枯渇からの復旧 を参照 |
| スリープ復帰後 `colima status` が固まる（colima #460） | `ddev poweroff && colima restart --profile ddev && docker context use colima-ddev`（★`ddev poweroff` は全プロジェクトを停止する。他の作業者に確認してから実行★） |
| 証明書警告が出る | `mkcert -install` を再実行し、ブラウザを再起動 |
| `ddev start` が Mailpit のポート衝突で失敗 | 他プロジェクトと `mailpit_https_port` が重複している。`.ddev/config.yaml` の `mailpit_http_port` / `mailpit_https_port` を空き番号（2 刻み）へ変更して `ddev restart` |
| 新しく作った 2 つのプロジェクトが同じ Mailpit ポートになる | ポートの採番は DDEV の既知プロジェクト一覧（`~/.ddev/project_list.yaml`）とホストの待ち受け状況を見るが、**プロジェクトが一覧に載るのは `ddev start` した時点**。生成しただけのものは次の採番から見えない。続けて作る場合は 1 つずつ `ddev start` まで済ませるか、2 つ目以降に `--mailpit-port` を明示指定する |
| 使っていないはずのポートを避けて採番される | DDEV 以外のアプリがそのポートで待ち受けている。生成時に `[info] <port> はホスト上で待ち受け中のため繰り上げます。` が出る。`lsof -nP -iTCP:<port> -sTCP:LISTEN` で相手を特定できる |
| `dev-down.sh` を実行したのに他プロジェクトまで止まった | 旧版のスクリプトが残っている（旧 `dev-down.sh` は `ddev poweroff` + `colima stop` を実行していた）。テンプレートを再生成して差し替える |
| `disable_settings_management` を `true` にしたら DB に繋がらない | `wp-config-ddev.php` 生成前に `true` にした可能性。一旦 `false` に戻して `ddev restart` → 生成確認 → `true` |
| `ddev start` が `Container ... Recreate / No such container` で失敗（`colima delete` 後によく起きる） | Colima の data ディスクは VM 削除でも永続化されるため、古い container 参照が containerd metadata に残っている。次で VM 内の docker state を初期化（**DB 投入前のみ**。投入後は volume データも消える。**共有 VM 上の全プロジェクトの volume に影響するため、他プロジェクトが構築済みなら実行しないこと**）: `colima ssh --profile ddev -- sudo systemctl stop docker docker.socket && colima ssh --profile ddev -- sudo rm -rf /var/lib/docker/containers /var/lib/docker/volumes/metadata.db && colima ssh --profile ddev -- sudo systemctl start docker && ddev poweroff && ddev start` |
| テンプレートを再生成したら独自設定（`docroot` / `upload_dirs` / `web_environment` など）が消えた | `--force` は `.ddev/config.yaml` を丸ごと置き換える。独自設定は `.ddev/config.project.yaml`（DDEV が `config.*.yaml` として自動マージする）へ移す。**ファイル名に `local` を入れないこと** — `.ddev/.gitignore`（ddev-generated）が `/config.local.y*ml` と `/config.*.local.y*ml` を除外するため、コミットされなくなる |
| 起動後の `ddev wp` で `mbstring.{http_input,http_output,internal_encoding} is deprecated` が出る | PHP 8.2+ で deprecated。`.ddev/php/__PROJECT_NAME__.ini` で空文字に上書きするか、テンプレ最新版を取り込む |

### ディスク枯渇からの復旧

`ddev start` が `Your Docker install has only N available disk space` を出し、
web コンテナが `No space left on device` で exit する場合。

**共有 VM のディスクは全プロジェクトで共用しているため、1 プロジェクトの肥大が
全プロジェクトを停止させる。** 復旧作業中も他プロジェクトが使えない点に注意すること。

VM 内の使用量を確認する:

```bash
colima ssh --profile ddev -- df -h /mnt/lima-colima-ddev
docker exec ddev-__PROJECT_NAME__-db du -ah /var/lib/mysql | sort -rh | head -20
```

`xhgui/results.ibd` が肥大している場合はプロファイル結果の蓄積が原因（実績: 85GB）。
DB ごと削除する。プロジェクト DB `db` には影響しない:

```bash
docker builder prune -af                                   # DROP の書き込み領域を確保
docker exec ddev-__PROJECT_NAME__-db mariadb -uroot -proot -e "DROP DATABASE IF EXISTS xhgui;"
```

**VM 内で削除してもホスト側のディスクイメージは縮まない。** 一度膨らんだイメージを
回収するには fstrim が必要（実績: 92GB → 8.5GB）:

```bash
colima ssh --profile ddev -- sudo fstrim -av
du -sh ~/.colima/_lima/_disks/colima-ddev/    # 回収されたか確認
```

再発防止は `.ddev/config.yaml` の `xhprof_mode: prof`（テンプレート既定）と、
§ VM ディスク使用量の定期確認 の運用。

---

> **注意（重要）**: `colima delete --profile ddev` は共有 VM を消す。
> **全プロジェクトの環境が同時に失われる**ため、通常運用では絶対に実行しないこと。
> なお VM ディスクを消しても **データディスク（`/var/lib/docker` 配下）は別管理で残る**。
> 意図的にフルクリーンしたい場合は上記の docker state 初期化手順を併用する。
> いずれも、全プロジェクトの DB を `ddev export-db` で退避したうえで実行すること。
