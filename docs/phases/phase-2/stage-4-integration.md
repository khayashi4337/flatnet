# Stage 4: Podman統合とGateway連携

## 概要

Phase 1 で構築した Gateway（OpenResty）と Phase 2 の CNI プラグインを連携させ、エンドツーエンドでの動作を確認する。社内メンバーがブラウザから Flatnet IP のコンテナにアクセスできる状態を完成させる。

## ブランチ戦略

- ブランチ名: `phase2/stage-4-integration`
- マージ先: `master`

## インプット（前提条件）

- Stage 3 完了（ネットワーク設定が動作）
- Phase 1 完了（Gateway が動作している）
- コンテナに Flatnet IP が割り当て可能
- ホスト-コンテナ間の通信が可能

## 目標

1. Gateway から Flatnet IP のコンテナに HTTP アクセスできる
2. 複数コンテナの同時運用ができる
3. コンテナのライフサイクル（起動/停止/再起動）が正常に動作
4. エラーケースの処理が適切
5. 運用に必要なドキュメントが整備される

## 手段

### エンドツーエンド構成

```
[社内 LAN: ブラウザ]
    │
    ▼ HTTP :80
[Windows: OpenResty Gateway]
    │
    ▼ proxy_pass http://10.87.1.x:port
[WSL2: flatnet-br0]
    │
    ▼ veth pair
[Container: 10.87.1.x]
```

---

## Sub-stages

### Sub-stage 4.1: Windows-WSL2 ルーティング設定

**内容:**
- Windows から WSL2 内の Flatnet サブネット（10.87.1.0/24）への経路設定
- WSL2 の IP フォワーディング有効化
- iptables/nftables 設定（必要に応じて）

**Windows 側設定:**
```powershell
# WSL2 の IP を取得
$wsl_ip = wsl hostname -I | ForEach-Object { $_.Trim().Split()[0] }

# Flatnet サブネットへのルート追加
route add 10.87.1.0 mask 255.255.255.0 $wsl_ip
```

**WSL2 側設定:**
```bash
# IP フォワーディング有効化
sudo sysctl -w net.ipv4.ip_forward=1

# 永続化
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-flatnet.conf
```

**完了条件:**
- [ ] Windows から `ping 10.87.1.1`（ブリッジ）が通る
- [ ] Windows から `ping 10.87.1.x`（コンテナ）が通る
- [ ] ルート設定が再起動後も維持される方法が文書化

---

### Sub-stage 4.2: OpenResty 設定更新

**内容:**
- Flatnet IP へのプロキシ設定
- 動的ルーティング（Lua）の検討
- ヘルスチェック設定

**nginx.conf 設定例:**
```nginx
upstream flatnet_forgejo {
    server 10.87.1.2:3000;
}

server {
    listen 80;
    server_name forgejo.local;

    location / {
        proxy_pass http://flatnet_forgejo;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

**完了条件:**
- [ ] OpenResty から Flatnet IP のコンテナに接続できる
- [ ] HTTP リクエストが正しくプロキシされる
- [ ] 設定変更が nginx reload で反映される

---

### Sub-stage 4.3: 複数コンテナ運用テスト

**内容:**
- 複数コンテナの同時起動
- IP の競合がないことを確認
- コンテナ間通信のテスト
- リソース使用量の確認

**テストシナリオ:**
```bash
# 複数コンテナ起動
podman run -d --name web1 --network flatnet nginx
podman run -d --name web2 --network flatnet nginx
podman run -d --name db1 --network flatnet postgres

# IP 確認
podman inspect web1 web2 db1 | jq '.[].NetworkSettings.Networks.flatnet.IPAddress'

# コンテナ間通信テスト
podman exec web1 ping -c 3 <web2-ip>
podman exec web1 curl http://<db1-ip>:5432 || echo "Expected: connection refused (not HTTP)"
```

**完了条件:**
- [ ] 3つ以上のコンテナが同時に動作する
- [ ] 各コンテナに異なる IP が割り当てられる
- [ ] コンテナ間で通信できる

---

### Sub-stage 4.4: ライフサイクルテスト

**内容:**
- コンテナの起動/停止/再起動
- IP の再利用
- 異常終了時のクリーンアップ
- CNI CHECK コマンドの動作確認

**テストシナリオ:**
```bash
# 通常ライフサイクル
podman run -d --name lifecycle-test --network flatnet nginx
podman stop lifecycle-test
podman start lifecycle-test  # 同一 IP が割り当てられるか？
podman rm lifecycle-test

# 異常終了シミュレーション
podman run -d --name crash-test --network flatnet nginx
podman kill crash-test
# IP が解放されているか確認

# 再起動テスト
podman run -d --name restart-test --network flatnet nginx
podman restart restart-test
```

**完了条件:**
- [ ] 停止/開始で IP が維持される（または適切に再割り当て）
- [ ] 強制終了後もリソースリークがない
- [ ] 再起動が正常に動作する

---

### Sub-stage 4.5: エラーハンドリング強化

**内容:**
- IP 枯渇時の動作
- 不正な設定でのエラーメッセージ
- ログ出力の改善
- 診断用コマンドの追加

**対応すべきエラーケース:**
1. IP アドレス枯渇
2. ブリッジ作成失敗（権限不足等）
3. netns が存在しない
4. veth 作成失敗
5. 設定ファイルの構文エラー

**完了条件:**
- [ ] 各エラーケースで適切なエラーメッセージが出力される
- [ ] エラー時に中途半端なリソースが残らない
- [ ] ログから問題の原因が特定できる

---

### Sub-stage 4.6: ドキュメント整備

**内容:**
- セットアップ手順書
- トラブルシューティングガイド
- 運用手順書
- アーキテクチャ図の更新

**作成するドキュメント:**
1. `docs/setup/phase-2-setup.md` - セットアップ手順
2. `docs/operations/troubleshooting.md` - トラブルシューティング
3. `docs/operations/cni-operations.md` - CNI 運用手順

**完了条件:**
- [ ] 別の環境で手順書通りにセットアップできる
- [ ] よくある問題と解決方法が文書化されている
- [ ] コンポーネント図が Phase 2 の状態を反映している

---

## 成果物

1. Windows ルーティングスクリプト
2. OpenResty 設定ファイル更新
3. `docs/setup/phase-2-setup.md` - セットアップ手順
4. `docs/operations/troubleshooting.md` - トラブルシューティング
5. 統合テストスクリプト

## 完了条件

- [ ] 社内 LAN のブラウザから Flatnet コンテナにアクセスできる
- [ ] 複数コンテナが同時に動作し、それぞれにアクセスできる
- [ ] コンテナの起動/停止が正常に動作する
- [ ] エラー時に適切なメッセージが表示される
- [ ] セットアップ手順書で別環境に構築できる

## Phase 2 完了チェックリスト

Phase 2 全体としての完了を確認:

- [ ] **機能要件**
  - [ ] `podman run --network flatnet` でコンテナが起動する
  - [ ] コンテナに Flatnet IP が割り当てられる
  - [ ] Gateway からコンテナに HTTP アクセスできる
  - [ ] 社内メンバーがブラウザからアクセスできる

- [ ] **非機能要件**
  - [ ] コンテナ起動時間への影響が許容範囲（+1秒以内）
  - [ ] メモリリークがない
  - [ ] ログが適切に出力される

- [ ] **運用要件**
  - [ ] セットアップ手順書が存在する
  - [ ] トラブルシューティングガイドが存在する
  - [ ] Phase 3 への拡張ポイントが明確

## 次のフェーズ（Phase 3）への接続点

Phase 3（マルチホスト対応）で拡張が必要な箇所:

1. **IPAM**: ホスト間での IP 重複を避ける仕組み
2. **ルーティング**: 他ホストの Flatnet サブネットへの経路
3. **ブリッジ → オーバーレイ**: Nebula トンネルとの連携
4. **Lighthouse 連携**: ノード登録と発見

これらの拡張点を意識した設計になっていることを確認する。

## 参考リンク

- [OpenResty Documentation](https://openresty.org/en/docs/)
- [WSL2 Networking](https://learn.microsoft.com/en-us/windows/wsl/networking)
- [Podman Network Commands](https://docs.podman.io/en/latest/markdown/podman-network.1.html)
