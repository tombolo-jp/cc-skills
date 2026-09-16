# 移行手順 — プロジェクト専用 Colima VM から共有 VM へ

旧方式（プロジェクトごとに Colima プロファイルを 1 つ作る構成）で構築済みの環境を、
ホスト共通の共有 VM（プロファイル `ddev`）へ移す**一度きり**の手順。

## 適用条件

**次のいずれにも当てはまらない場合、この手順は不要。** 新規構築なら `setup.md` から始めること。

- [ ] `~/.colima/` にプロジェクト名のプロファイル（`ddev` 以外）が存在する
- [ ] `.colima/<プロジェクト名>.yaml` がリポジトリに残っている
- [ ] `docker context ls` に `colima-<プロジェクト名>` がある

## 進め方の原則

- **移行対象が複数ある場合は、全プロジェクトを共有 VM 上で疎通確認し終えるまで、
  旧 VM を消さないこと。** 本手順の最後に置いてある破棄ステップは、
  最後の 1 プロジェクトの確認が終わってから初めて実行する。
- 旧 VM は停止するだけなら元に戻せる。破棄は元に戻せない。
- 途中で問題が起きたら、旧 VM を起動し直せば従来どおり作業できる（末尾の「困ったとき」表を参照）。
  旧 VM を破棄する §8 まで進まない限り、いつでも元に戻せる。

---

## 1. DB を退避（★最初に必ず実施★）

移行対象の**全プロジェクト**について、旧 VM が動いているうちにダンプを取る。
以降の手順で DB データが失われても、ここから復元できる状態を先に作る。

```bash
# 旧 VM を起動して docker context を合わせる
colima start --profile <旧プロファイル名>
docker context use colima-<旧プロファイル名>

# プロジェクトのディレクトリで実行
cd <プロジェクトのパス>
ddev start
mkdir -p ~/ddev-migration
ddev export-db --file=~/ddev-migration/<プロジェクト名>-$(date +%Y%m%d-%H%M%S).sql.gz
```

**確認**: 出力されたファイルのサイズが 0 でないこと。

```bash
ls -lh ~/ddev-migration/
```

> ダンプには本番相当の個人情報が含まれうる。チャット等では受け渡さず、
> 移行完了後は §9 の後始末で削除するか、安全な場所へ退避すること。

移行対象が複数ある場合は、ここで**全プロジェクト分**のダンプを取っておく。

### ★重要★ 追加のデータベースが無いか確認する

**`ddev export-db` は既定で `db` データベースだけを出力する。** 1 つのリポジトリに複数の WordPress を
同居させている場合など、別の DB を使うサイトがあるとダンプに含まれず、移行後に
「データベース接続確立エラー」になる。**旧 VM を停止する前に必ず確認すること。**

```bash
ddev mysql -N -e "show databases"
```

`db` ・ `information_schema` ・ `mysql` ・ `performance_schema` ・ `sys` ・ `test` 以外が出てきたら、
その DB も個別にダンプする。

```bash
ddev export-db --database=<DB名> \
  --file=~/ddev-migration/<プロジェクト名>-<DB名>-$(date +%Y%m%d-%H%M%S).sql.gz
```

別 DB が現れるのは「1 つのリポジトリに複数の WordPress が同居している」場合がほとんどなので、
`wp-config.php` の数を数えるだけでも短時間で見当がつく。

```bash
find . -name wp-config.php -not -path '*/node_modules/*' -not -path '*/vendor/*'
```

2 つ以上見つかったら、それぞれの `DB_NAME` を確認する。`wp-config-ddev.php` を読み込まず
`DB_NAME` を固定しているファイルが、別 DB を使っているサイトである。

```bash
grep -n "DB_NAME" <見つかった wp-config.php>
```

> 旧 VM を破棄する §8 まで進むと、取りこぼした DB は**二度と取り出せない**。
> §6 の疎通確認では、サブディレクトリで動いている別サイトも開くこと。

---

## 2. 旧プロファイルを停止

```bash
ddev poweroff
colima stop --profile <旧プロファイル名>
```

移行対象が複数ある場合は、すべての旧プロファイルを停止する。
**この時点では削除しない。**

---

## 3. テンプレートを再生成

共有 VM 方式の設定一式へ差し替える。`--force` を付けると既存ファイルを上書きするため、
手を入れた設定がある場合は先に差分を確認すること。

> **★ 実行前に必ず ★** `.ddev/config.yaml` にテンプレート標準を超える設定（`docroot` / `database` /
> `upload_dirs` / `webimage_extra_packages` / `web_environment` / `hooks`）がある場合は、
> 下記「独自設定は `config.project.yaml` へ分離する」を**先に**実施すること。
> `--force` はこのファイルを丸ごと置き換えるため、分離前に実行すると独自設定が失われる。
> `.ddev/` が gitignore 対象のリポジトリでは git から復元できない。

```bash
cd <プロジェクトのパス>
bash <スキルのパス>/scripts/generate.sh \
  --php <PHPバージョン> --mariadb <MariaDBバージョン> --fqdn <FQDN> \
  --name <現行の DDEV プロジェクト名> --setup-doc <既存の手順書のパス> \
  --target . --force
```

### `--name` と `--setup-doc` を省略しないこと

**移行では `--name` の明示が必須。** 省略すると `--target` のディレクトリ名から
プロジェクト名が導出される（例: `my_project` → `my-project`）。現行の
`.ddev/config.yaml` の `name:` と食い違うと、DDEV から見て別プロジェクトになり、
URL も DB volume も新規に作られる。移行ではなく新規構築になってしまう。

`--setup-doc` も、既存の手順書がある場所（`.claude/tasks_archive/docker/setup.md` など）に
合わせて渡す。省略すると既定パスへ新しい手順書が出力され、共有 VM 方式に更新されていない
古い手順書が別の場所に残り続ける。

`--force` が上書きするファイル:

| ファイル | 変更内容 |
|---|---|
| `.colima/ddev.yaml` | **新規**（共有プロファイル定義。cpu 4 / memory 8GiB / disk 80GiB） |
| `scripts/colima-start.sh` | プロファイルを `ddev` 固定へ。既存 VM との差異警告を追加 |
| `scripts/colima-stop.sh` | **新規**（共有 VM 停止） |
| `scripts/dev-up.sh` | プロファイル固定。Mailpit URL の動的取得 |
| `scripts/dev-down.sh` | `ddev poweroff` → `ddev stop`（このプロジェクトのみ停止） |
| `.ddev/config.yaml` | `mailpit_http_port` / `mailpit_https_port` を追加 |
| `.ddev/mysql/<プロジェクト名>.cnf` | チューニング値を標準規模向けへ縮小 |
| `.ddev/php/<プロジェクト名>.ini` | `memory_limit` などを縮小 |
| `setup.md` / `migrate.md` | 共有 VM 前提の手順書 |

### `--force` を使わず手で当てる場合

生成先を別ディレクトリにして差分を見ながら反映してもよい。

```bash
bash <スキルのパス>/scripts/generate.sh \
  --php <PHPバージョン> --mariadb <MariaDBバージョン> --fqdn <FQDN> \
  --target /tmp/ddev-new
diff -ru . /tmp/ddev-new 2>/dev/null | less
```

### `.ddev/config.yaml` を上書きした場合の注意

**`disable_settings_management` が `false` に戻る。**
`wp-config-ddev.php` と `wp-config.php` の require 行が既にある環境では、
`ddev start` する前に `true` へ戻しておくこと。`false` のままだと DDEV が
`wp-config.php` を自動編集し、独自定数が壊れる恐れがある。

```bash
# .ddev/config.yaml: disable_settings_management: false → true
grep -n 'disable_settings_management' .ddev/config.yaml
```

### 独自設定は `config.project.yaml` へ分離する

`--force` は `.ddev/config.yaml` を丸ごと置き換える。テンプレート標準を超える設定
（`docroot` / `database` / `upload_dirs` / `webimage_extra_packages` / `web_environment` / `hooks` など）を
上書き後の `config.yaml` へ手で書き戻す運用は、次の再生成でまた消えるため破綻する。

DDEV は `.ddev/config.yaml` と `.ddev/config.*.yaml` をファイル名のアルファベット順にマージする。
独自設定は再生成の対象外になる `.ddev/config.project.yaml` へ移しておくこと。

```yaml
# .ddev/config.project.yaml — generate.sh が触らない追加設定
docroot: app/public
web_environment:
  - WP_DEBUG=false
```

- **ファイル名に `local` を含めてはならない。** `.ddev/.gitignore`（ddev-generated）が
  `/config.local.y*ml` と `/config.*.local.y*ml` を除外しているため、`config.local.yaml` に
  書いた設定はコミットされず、チームの他のメンバーには反映されない。
- リスト（`upload_dirs` / `webimage_extra_packages` / `web_environment`）は**常に完全な一覧**を書く。
  マージが上書き・追記のどちらであっても同じ結果になり、DDEV 側の挙動に依存しなくなる。
- PHP のチューニングを個別に足す場合も同様に、`generate.sh` の出力先（`.ddev/php/<プロジェクト名>.ini`）
  ではなく `.ddev/php/zz-<プロジェクト名>-local.ini` を新設する（`.ddev/php/*.ini` は全て読まれ、後勝ち）。

**確認**: `ddev debug configyaml` でマージ後の実効値を見る（Docker が動いている必要がある）。

### 旧ファイルの後片付け（任意）

- `.colima/<旧プロファイル名>.yaml` — 不要になる。削除してよい。
- `.gitignore` の `.colima/<旧プロファイル名>.local.yaml` の行 — 無害な残骸。削除してよい
  （新しい行 `.colima/ddev.local.yaml` は再生成時に追記済み）。**直前のコメント行**
  （「チーム標準は `.colima/<旧プロファイル名>.yaml` のみコミット」）も一緒に消すこと。
  行だけ消すと旧プロファイル名を指す説明が残る。

---

## 4. 共有 VM を作成

最初の 1 プロジェクトでのみ VM が作成される。2 つ目以降は既存 VM に相乗りする。

```bash
cd <プロジェクトのパス>
./scripts/colima-start.sh
```

**確認**: `colima list` に `ddev` が Running で並び、cpu 4 / memory 8GiB / disk 80GiB になっていること。

```bash
colima list
docker context show      # colima-ddev であること
```

---

## 5. プロジェクトを起動して DB を戻す

```bash
cd <プロジェクトのパス>
ddev start

# 投入用の I/O 高速化設定を一時的に有効化
mv .ddev/mysql/zz-import.cnf.disabled .ddev/mysql/zz-import.cnf
ddev restart

ddev import-db --file=~/ddev-migration/<退避したファイル>

# §1 で追加の DB をダンプした場合は、それぞれ --database を付けて投入する
# ddev import-db --database=<DB名> --file=~/ddev-migration/<そのDBのファイル>

# ★戻し忘れ厳禁★ I/O 設定を無効化に戻す
mv .ddev/mysql/zz-import.cnf .ddev/mysql/zz-import.cnf.disabled
ddev restart
```

---

## 6. 疎通確認

```bash
open https://<FQDN>
ddev describe
```

- [ ] サイトが表示され、証明書警告が出ない
- [ ] WP 管理画面にログインできる
- [ ] 移行前と同じコンテンツが表示される（記事数・メディア）
- [ ] `ddev describe` の URL がポートなしの `https://<FQDN>` である
- [ ] Mailpit（`ddev describe` に表示される URL）が開く
- [ ] `.ddev/config.yaml` の `disable_settings_management` が `true` に戻っている
- [ ] `ls .ddev/mysql/` に `zz-import.cnf`（`.disabled` の付かないもの）が無い
      — §5 の戻し忘れ検出。有効なままだとクラッシュ時に InnoDB が壊れる

移行対象が複数ある場合は、**ここまでを全プロジェクト分繰り返す**（§3〜§6）。
2 つ目以降は §4 で VM 作成が起きず「既に起動中」と表示されるのが正常。

---

## 7. 同時起動の確認（移行対象が複数の場合）

```bash
# それぞれのディレクトリで
./scripts/dev-up.sh
```

- [ ] 全サイトが同時にポートなしの HTTPS URL で開く
- [ ] 各プロジェクトの Mailpit が別ポートで開き、メールが混ざらない
- [ ] 1 つで `./scripts/dev-down.sh` を実行しても、他は動き続ける

---

## 8. 旧 VM を破棄（★全プロジェクトの確認が終わってから★）

**前提条件（すべて満たすこと）**:

- [ ] 移行対象の**全プロジェクト**が §6 の疎通確認を通過している
- [ ] §1 のダンプが手元に残っている
- [ ] 旧 VM でしか動かしていないプロジェクトが 1 つも残っていない

`colima delete` は **VM とそのデータを元に戻せない形で削除する**。
上のいずれかが未達なら、このステップは実行せず旧 VM を停止したまま残しておくこと
（停止中の VM はディスクを占有するが、動作の邪魔にはならない）。

```bash
colima delete --profile <旧プロファイル名>
```

移行対象が複数ある場合は、旧プロファイルごとに繰り返す。

**確認**: `colima list` に `ddev` だけが残っていること。

```bash
colima list
docker context ls        # colima-<旧プロファイル名> が消えていること
```

### ★重要★ data disk は `colima delete` では消えない

**`colima delete` は VM を削除するが、data disk は残したままになる。** ディスクを回収するには
別途 `limactl disk delete` が必要で、これを忘れると「旧 VM を消したのに空き容量が増えない」ことになる。

```bash
export LIMA_HOME=~/.colima/_lima
limactl disk ls                    # IN-USE-BY が空のものが回収対象
du -sh ~/.colima/_lima/_disks/*    # 実使用量
```

`colima list` に存在しないプロファイルの disk だけを削除する（`colima-ddev` は共有 VM が使用中なので残す）。

```bash
limactl disk delete colima-<旧プロファイル名> [colima-<旧プロファイル名> ...]
```

**確認**: `df -h /System/Volumes/Data` の空き容量が、削除した disk の実使用量ぶん増えていること。

---

## 9. ダンプの後始末

`~/ddev-migration/` のダンプには本番相当の個人情報が含まれうる。
移行完了後、次のいずれかを必ず実施する。

```bash
# 削除する場合
rm -rf ~/ddev-migration

# 保管する場合は暗号化ボリューム等、権限管理された場所へ移す
```

---

## 困ったとき

| 症状 | 対処 |
|---|---|
| 共有 VM 上で `ddev start` がポート衝突で失敗 | 他プロジェクトと Mailpit ポートが重複している。`.ddev/config.yaml` の `mailpit_http_port` / `mailpit_https_port` を空き番号（2 刻み）へ変更して `ddev restart` |
| `colima list` の cpu/memory/disk が期待値と違う | 既に別プロジェクトが VM を作成済み。`setup.md` の「共有 VM のリソースを変更する」に従って揃える |
| 移行後にサイトが表示されない | 旧 VM を起動し直せば従来どおり作業できる（`colima start --profile <旧プロファイル名> && docker context use colima-<旧プロファイル名> && ddev start`）。旧 VM を破棄する前ならいつでも戻せる |
| DB の内容が移行前と違う | §1 のダンプから `ddev import-db` で入れ直す |
