# Stage 4: ドキュメント整備

## 概要

Phase 1 の成果を他者が再現できるよう、セットアップ手順書とトラブルシューティングガイドを整備する。

## ブランチ戦略

- ブランチ名: `phase1/stage-4-documentation`
- マージ先: `master`

## インプット（前提条件）

- Stage 3 完了（Forgejo が社内 LAN からアクセス可能）
- 実際のセットアップ経験と発生した問題の記録
- Stage 1-3 の各ドキュメントが更新されている

## 目標

- 別の環境でも手順書通りに構築できる
- よくある問題と解決策がまとまっている
- 運用時の注意点が明確になっている

## 手段

- Stage 1-3 で行った作業を手順書としてまとめる
- 発生した問題と解決策を記録
- 別環境でのテストセットアップを実施

## ディレクトリ構成

```
[WSL2] /home/kh/prj/flatnet/
       ├── docs/
       │   ├── guides/
       │   │   ├── phase1-setup-guide.md        ← セットアップ手順書
       │   │   ├── phase1-troubleshooting.md    ← トラブルシューティング
       │   │   ├── phase1-operations.md         ← 運用ガイド
       │   │   └── phase1-validation-checklist.md ← 検証チェックリスト
       │   └── phases/
       │       └── phase-1/
       │           ├── stage-1-openresty-setup.md
       │           ├── stage-2-wsl2-proxy.md
       │           ├── stage-3-forgejo-integration.md
       │           └── stage-4-documentation.md
       └── examples/
           ├── openresty/
           │   └── nginx.conf                   ← nginx.conf サンプル
           └── forgejo/
               └── run.sh                       ← 起動スクリプトサンプル
```

## Sub-stages

### Sub-stage 4.1: セットアップ手順書

**内容:**

- 環境要件のまとめ
- OpenResty インストール手順
- WSL2 設定手順
- Forgejo セットアップ手順
- 設定ファイルのテンプレート

**手順:**

1. **ドキュメントディレクトリを作成:**

```bash
mkdir -p /home/kh/prj/flatnet/docs/guides
mkdir -p /home/kh/prj/flatnet/examples/openresty
mkdir -p /home/kh/prj/flatnet/examples/forgejo
```

2. **セットアップ手順書の構成:**

ファイル: `docs/guides/phase1-setup-guide.md`

```markdown
# Phase 1 セットアップガイド

## 環境要件

| 項目 | 要件 |
|------|------|
| OS | Windows 10/11 (21H2 以降) |
| WSL2 | Ubuntu 24.04 |
| Podman | 4.x 以上 |
| メモリ | 8GB 以上推奨 |
| ディスク | F: ドライブに 10GB 以上の空き |

## 1. OpenResty のインストール
（Stage 1 の内容を要約）

## 2. WSL2 プロキシの設定
（Stage 2 の内容を要約）

## 3. Forgejo のセットアップ
（Stage 3 の内容を要約）

## 4. 動作確認

## 5. よくある質問
```

3. **設定ファイルのサンプルを配置:**

```bash
# nginx.conf のサンプル
cp config/openresty/nginx.conf examples/openresty/

# Forgejo 起動スクリプトのサンプル
cp scripts/forgejo/run.sh examples/forgejo/
```

**完了条件:**

- [ ] セットアップ手順書が作成されている
  ```bash
  test -f docs/guides/phase1-setup-guide.md && echo "OK"
  # 期待出力: OK
  ```
- [ ] 環境要件が明記されている
  ```bash
  grep -c "Windows\|WSL2\|Podman" docs/guides/phase1-setup-guide.md
  # 期待出力: 3 以上
  ```
- [ ] 設定ファイルのサンプルが配置されている
  ```bash
  ls examples/openresty/nginx.conf examples/forgejo/run.sh
  # 期待出力: ファイルが表示される
  ```

### Sub-stage 4.2: トラブルシューティングガイド

**内容:**

- Stage 1-3 のトラブルシューティング内容を統合
- ログの確認方法
- デバッグのヒント

**手順:**

1. **トラブルシューティングガイドの構成:**

ファイル: `docs/guides/phase1-troubleshooting.md`

```markdown
# Phase 1 トラブルシューティングガイド

## ログの場所

| コンポーネント | ログの場所 |
|---------------|-----------|
| OpenResty | F:\flatnet\logs\error.log |
| OpenResty アクセスログ | F:\flatnet\logs\access.log |
| Forgejo | ~/forgejo/data/gitea/log/ |
| Podman | journalctl --user -u forgejo |

## 1. OpenResty 関連

### 1.1 起動しない
### 1.2 ポートが使用中
### 1.3 設定エラー

## 2. WSL2 プロキシ関連

### 2.1 502 Bad Gateway
### 2.2 IP アドレスが変わった
### 2.3 接続がタイムアウト

## 3. Forgejo 関連

### 3.1 コンテナが起動しない
### 3.2 ログインできない
### 3.3 Git push でエラー

## 4. ネットワーク関連

### 4.1 LAN からアクセスできない
### 4.2 Firewall の問題

## 5. デバッグのヒント

- nginx -t で設定テスト
- curl -v で詳細なリクエスト確認
- podman logs でコンテナログ確認
```

2. **Stage 1-3 のトラブルシューティング内容を参照して詳細を記載**

**完了条件:**

- [ ] トラブルシューティングガイドが作成されている
  ```bash
  test -f docs/guides/phase1-troubleshooting.md && echo "OK"
  # 期待出力: OK
  ```
- [ ] 主要なエラーパターンがカバーされている
  ```bash
  grep -c "##" docs/guides/phase1-troubleshooting.md
  # 期待出力: 10 以上（セクション数）
  ```
- [ ] ログの確認方法が記載されている
  ```bash
  grep -i "log" docs/guides/phase1-troubleshooting.md | head -3
  # 期待出力: ログ関連の記載
  ```

### Sub-stage 4.3: 運用ガイド

**内容:**

- 日常運用で必要な作業
- バックアップとリストア
- アップデート手順

**手順:**

1. **運用ガイドの構成:**

ファイル: `docs/guides/phase1-operations.md`

```markdown
# Phase 1 運用ガイド

## 日常運用

### サービスの起動・停止

| 操作 | コマンド |
|------|----------|
| OpenResty 起動 | `Start-Service OpenResty` |
| OpenResty 停止 | `Stop-Service OpenResty` |
| OpenResty 再起動 | `Restart-Service OpenResty` |
| Forgejo 起動 | `systemctl --user start forgejo` |
| Forgejo 停止 | `systemctl --user stop forgejo` |
| Forgejo 再起動 | `systemctl --user restart forgejo` |

### WSL2 IP 変更時の対応

WSL2 を再起動すると IP アドレスが変わる場合があります。

\`\`\`bash
./scripts/update-upstream.sh --reload
\`\`\`

### ログの確認

\`\`\`powershell
# OpenResty エラーログ
Get-Content F:\flatnet\logs\error.log -Tail 50

# OpenResty アクセスログ
Get-Content F:\flatnet\logs\access.log -Tail 50
\`\`\`

\`\`\`bash
# Forgejo ログ
podman logs forgejo --tail 50
\`\`\`

## バックアップ

### 対象データ

| データ | 場所 | 重要度 |
|--------|------|--------|
| Forgejo データ | ~/forgejo/data/ | 高 |
| Forgejo 設定 | ~/forgejo/config/ | 高 |
| nginx 設定 | config/openresty/ | Git 管理 |

### バックアップ手順

\`\`\`bash
# Forgejo を停止
systemctl --user stop forgejo

# バックアップ
tar czf forgejo-backup-$(date +%Y%m%d).tar.gz ~/forgejo/

# Forgejo を再開
systemctl --user start forgejo
\`\`\`

## リストア

\`\`\`bash
# Forgejo を停止
systemctl --user stop forgejo

# 既存データを退避
mv ~/forgejo ~/forgejo.old

# バックアップからリストア
tar xzf forgejo-backup-YYYYMMDD.tar.gz -C ~/

# Forgejo を再開
systemctl --user start forgejo
\`\`\`

## アップデート

### Forgejo のアップデート

\`\`\`bash
# 新しいイメージを pull
podman pull codeberg.org/forgejo/forgejo:9

# Forgejo を再起動
systemctl --user restart forgejo
\`\`\`

### OpenResty のアップデート

1. 新しいバージョンをダウンロード
2. OpenResty を停止
3. F:\flatnet\openresty を置き換え
4. OpenResty を起動
```

**完了条件:**

- [ ] 運用ガイドが作成されている
  ```bash
  test -f docs/guides/phase1-operations.md && echo "OK"
  # 期待出力: OK
  ```
- [ ] バックアップ手順が記載されている
  ```bash
  grep -i "backup\|バックアップ" docs/guides/phase1-operations.md | head -3
  # 期待出力: バックアップ関連の記載
  ```
- [ ] 再起動手順が記載されている
  ```bash
  grep -i "restart\|再起動" docs/guides/phase1-operations.md | head -3
  # 期待出力: 再起動関連の記載
  ```

### Sub-stage 4.4: 検証テスト

**内容:**

- 手順書に従って環境構築をテスト
- 不明瞭な点、抜け漏れの洗い出し
- 手順書の修正

**手順:**

1. **検証チェックリストを作成:**

ファイル: `docs/guides/phase1-validation-checklist.md`

```markdown
# Phase 1 検証チェックリスト

## 環境情報

- 検証日:
- 検証者:
- Windows バージョン:
- WSL2 ディストリビューション:

## Stage 1: OpenResty セットアップ

- [ ] OpenResty がインストールできた
- [ ] nginx -v でバージョンが表示される
- [ ] http://localhost/ でテストページが表示される
- [ ] http://localhost/health で OK が返る
- [ ] Firewall ルールが追加されている
- [ ] デプロイスクリプトが動作する

## Stage 2: WSL2 プロキシ設定

- [ ] WSL2 IP を取得できる
- [ ] テストサーバーにプロキシ経由でアクセスできる
- [ ] IP 更新スクリプトが動作する
- [ ] プロキシヘッダーが設定されている

## Stage 3: Forgejo 統合

- [ ] Forgejo コンテナが起動する
- [ ] 初期設定ウィザードが完了できる
- [ ] 社内 LAN からアクセスできる
- [ ] git clone が成功する
- [ ] git push が成功する
- [ ] WSL2 再起動後も自動復旧する

## 発見した問題

| 問題 | 発生箇所 | 解決策 |
|------|----------|--------|
| | | |

## 手順書への修正提案

| 箇所 | 修正内容 |
|------|----------|
| | |
```

2. **検証を実施:**

- 可能であれば別の Windows 環境でテスト
- または同環境で OpenResty をアンインストールしてから再セットアップ

3. **発見した問題を手順書に反映:**

- 不明瞭な表現を修正
- 抜け漏れの手順を追加
- エラーケースをトラブルシューティングに追加

**完了条件:**

- [ ] 検証チェックリストが作成されている
  ```bash
  test -f docs/guides/phase1-validation-checklist.md && echo "OK"
  # 期待出力: OK
  ```
- [ ] 検証が実施され、チェックリストが記入されている
- [ ] 発見した問題が手順書に反映されている
  ```bash
  git diff docs/guides/phase1-setup-guide.md | head -20
  # 期待出力: 修正内容（あれば）
  ```
- [ ] 第三者レビューを実施（可能であれば）

## 成果物

### ドキュメント

| パス | 説明 |
|------|------|
| `docs/guides/phase1-setup-guide.md` | セットアップ手順書 |
| `docs/guides/phase1-troubleshooting.md` | トラブルシューティングガイド |
| `docs/guides/phase1-operations.md` | 運用ガイド |
| `docs/guides/phase1-validation-checklist.md` | 検証チェックリスト |

### サンプルファイル

| パス | 説明 |
|------|------|
| `examples/openresty/nginx.conf` | nginx.conf サンプル |
| `examples/forgejo/run.sh` | Forgejo 起動スクリプトサンプル |

## 完了条件

| 条件 | 確認コマンド |
|------|-------------|
| セットアップ手順書が完成 | `test -f docs/guides/phase1-setup-guide.md` |
| トラブルシューティングガイドが完成 | `test -f docs/guides/phase1-troubleshooting.md` |
| 運用ガイドが完成 | `test -f docs/guides/phase1-operations.md` |
| サンプルファイルが配置済み | `ls examples/openresty/ examples/forgejo/` |
| 別環境で構築確認済み | 検証チェックリストを確認 |

## トラブルシューティング

### ドキュメントが見つからない

**症状:** ドキュメントへのリンクが切れている

**対処:**

```bash
# ファイルの存在を確認
ls -la docs/guides/

# リンク先のパスを確認
grep -r "phase1-" docs/
```

### マークダウンのレンダリングが崩れる

**症状:** コードブロックや表が正しく表示されない

**対処:**

- コードブロックのバッククォートが3つであることを確認
- 表のヘッダー区切り行（`|---|---|`）があることを確認
- インデントにタブとスペースが混在していないか確認

## 備考

- ドキュメントは日本語で作成（社内向け）
- 必要に応じてスクリーンショットや図を追加
- Phase 2 以降で変更がある場合は、ドキュメントも更新すること
- 検証チェックリストは継続的に更新し、新しい問題が発見されたら追記する

## 次のステップ

Stage 4 完了で Phase 1 は終了。[Phase 2: CNI Plugin](../phase-2/) に進み、Podman のネットワークプラグインを開発する。
