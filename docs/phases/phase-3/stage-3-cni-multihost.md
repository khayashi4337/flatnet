# Stage 3: CNI Plugin マルチホスト拡張

## 概要

Phase 2 で実装した CNI Plugin をマルチホスト対応に拡張する。各ホストが異なる IP 範囲を割り当て、ホスト間でコンテナが相互に通信できるようにする。

## ブランチ戦略

- ブランチ名: `phase3/stage-3-cni-multihost`
- マージ先: `master`

## インプット（前提条件）

- Phase 2 完了（CNI Plugin が単一ホストで動作）
- Stage 2 完了（ホスト間トンネルが確立）
- 各ホストに一意のホスト ID が割り当てられている

## 目標

- 各ホストが衝突しない IP 範囲をコンテナに割り当てる
- 異なるホスト上のコンテナ間で通信ができる
- コンテナ情報を Gateway 間で共有する

## ディレクトリ構成

```
[Windows] F:\flatnet\
          ├── openresty\
          │   └── lualib\
          │       └── flatnet\        ← Gateway 間同期 Lua モジュール
          │           ├── registry.lua
          │           └── sync.lua
          └── config\
              └── openresty\
                  └── conf.d\
                      └── api.conf    ← コンテナ情報 API

[WSL2] /home/kh/prj/flatnet/
       ├── src/
       │   └── flatnet-cni/          ← CNI Plugin (Rust)
       │       └── src/
       │           ├── main.rs
       │           ├── config.rs     ← ホスト ID 対応
       │           └── registry.rs   ← 情報共有クライアント
       └── config/
           └── cni/
               └── flatnet.conflist  ← CNI 設定テンプレート
```

## 手段

- IP 割り当てロジックのホスト ID 対応
- コンテナ情報の同期機構（Gateway 間 HTTP API）
- クロスホストルーティングの設定

## Sub-stages

### Sub-stage 3.1: ホスト ID による IP 範囲分離

**内容:**
- 各ホストに一意のホスト ID を設定（1-254）
- IP 割り当てを `10.100.<host-id>.<container-id>` 形式に変更
- CNI Plugin の設定ファイルにホスト ID を追加

**例:**
```
Host A (ID: 1): 10.100.1.10, 10.100.1.11, ...
Host B (ID: 2): 10.100.2.10, 10.100.2.11, ...
```

**完了条件:**
- [ ] CNI Plugin がホスト ID を設定から読み込める
- [ ] コンテナに割り当てられる IP がホスト ID に基づいている
  ```bash
  # WSL2 で確認
  podman run --rm --network flatnet alpine ip addr
  # 期待: 10.100.<host-id>.X/24
  ```
- [ ] 同一ホスト内での IP 重複がない

### Sub-stage 3.2: クロスホストルーティング

**内容:**
- WSL2 内でのルーティングテーブル設定
- 他ホストの IP 範囲への経路を設定
- Nebula トンネル経由で転送されるようにする

**ルーティング例:**
```bash
# Host A (10.100.1.0/24) の WSL2 内
ip route add 10.100.2.0/24 via <windows-nebula-gw>
ip route add 10.100.3.0/24 via <windows-nebula-gw>
```

**完了条件:**
- [ ] WSL2 から他ホストの IP 範囲に経路が設定されている
  ```bash
  ip route | grep 10.100
  # 期待: 10.100.2.0/24 via <gateway> ...
  ```
- [ ] 他ホストのコンテナ IP に ping が通る
  ```bash
  # Host A の WSL2 から Host B のコンテナへ
  ping -c 4 10.100.2.10
  ```

### Sub-stage 3.3: コンテナ情報共有機構

**内容:**
- 各ホストのコンテナ情報（IP、ポート、サービス名）を共有する仕組み
- 実装案:
  1. **Lighthouse 拡張**: Nebula Lighthouse にメタデータを追加
  2. **専用レジストリ**: 軽量な Key-Value ストア（etcd, consul）
  3. **ファイルベース**: 共有ファイルシステム or Git
  4. **Gateway 間同期**: OpenResty 間で HTTP API 経由の同期

**推奨: 案 4（Gateway 間同期）**
- 理由: 追加インフラ不要、OpenResty の Lua で実装可能

**整合性モデル: Eventual Consistency**
- 各 Gateway はローカルにコンテナ情報をキャッシュ
- 変更は非同期で他 Gateway に伝播
- TTL（Time To Live）でキャッシュを自動失効
- 古い情報でルーティングした場合はエラーを検知して更新

**完了条件:**
- [ ] 各 Gateway が他ホストのコンテナ情報を取得できる
  ```bash
  # WSL2 から Gateway API を確認
  curl http://10.100.1.1:8080/api/containers
  ```
- [ ] コンテナ起動時に他 Gateway へ通知される
- [ ] コンテナ停止時に情報が削除される
- [ ] キャッシュ TTL が設定されている（デフォルト: 300秒）

### Sub-stage 3.4: Gateway のクロスホストプロキシ

**内容:**
- クライアントからのリクエストを適切なホストにルーティング
- ローカルにないコンテナへのリクエストを他 Gateway に転送
- Nebula トンネル経由での転送

**処理フロー:**
```
1. クライアント → Gateway A (HTTP リクエスト)
2. Gateway A: コンテナ情報をルックアップ
3. ローカルの場合 → 直接 WSL2 へプロキシ
4. 他ホストの場合 → Gateway B へ転送（Nebula 経由）
5. Gateway B → WSL2 B → コンテナ
6. レスポンスを逆経路で返す
```

**完了条件:**
- [ ] 他ホストのコンテナへのリクエストが正しくルーティングされる
  ```bash
  # 社内 LAN クライアントから Gateway A 経由で Host B のコンテナにアクセス
  curl -H "Host: container-b1.flatnet" http://<Gateway-A-IP>/
  ```
- [ ] レスポンスがクライアントに返る
- [ ] ルーティング決定がログに記録される
  ```powershell
  Get-Content F:\flatnet\logs\access.log | Select-String "container-b1"
  ```

### Sub-stage 3.5: CNI Plugin のマルチホスト対応

**内容:**
- CNI Plugin からコンテナ情報を共有機構に登録
- コンテナ削除時の情報クリーンアップ
- エラーハンドリングの強化

**完了条件:**
- [ ] コンテナ起動時に情報が共有機構に登録される
- [ ] コンテナ停止時に情報が削除される
- [ ] 共有機構への接続失敗時もローカル動作が継続する

## 成果物

| 種別 | パス | 説明 |
|------|------|------|
| CNI Plugin | `/opt/cni/bin/flatnet` | マルチホスト対応版バイナリ |
| CNI 設定 | `/etc/cni/net.d/flatnet.conflist` | ホスト ID 含む設定 |
| Lua モジュール | `F:\flatnet\openresty\lualib\flatnet\registry.lua` | コンテナ情報管理 |
| Lua モジュール | `F:\flatnet\openresty\lualib\flatnet\sync.lua` | Gateway 間同期 |
| OpenResty 設定 | `F:\flatnet\config\openresty\conf.d\api.conf` | 内部 API 設定 |
| スクリプト | `/home/kh/prj/flatnet/scripts/cross-host-routing.sh` | ルーティング設定 |

**ドキュメント成果物:**
- コンテナ情報共有 API 仕様（技術メモに記載）

## 完了条件

- [ ] 異なるホストのコンテナ同士が IP で通信できる
- [ ] Gateway がクロスホストリクエストを正しくルーティングする
- [ ] コンテナ情報がホスト間で共有されている
- [ ] クライアントは変わらず HTTP のみでアクセスできる

## 技術メモ

### CNI 設定ファイル拡張例

```json
{
  "cniVersion": "0.4.0",
  "name": "flatnet",
  "type": "flatnet",
  "hostId": 1,
  "ipRange": "10.100.1.0/24",
  "gateway": "10.100.1.1",
  "registryEndpoints": [
    "http://10.100.0.1:8080/api/containers"
  ]
}
```

### Gateway 間 API 例

**エンドポイント設計:**
- 各 Gateway は Nebula IP でリッスン（例: `http://10.100.1.1:8080`）
- 社内 LAN からは直接アクセス不可（Nebula ネットワーク内のみ）
- これにより Gateway 間通信は暗号化される

**OpenResty 設定（内部 API）:**

ファイル: `F:\flatnet\config\openresty\conf.d\api.conf`

```nginx
# 内部 API サーバー（Nebula ネットワーク内のみ）
server {
    listen 10.100.1.1:8080;  # Nebula IP でバインド

    location /api/containers {
        content_by_lua_file lualib/flatnet/api/containers.lua;
    }

    location /api/health {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
```

**API 仕様:**

```
# コンテナ登録（コンテナ起動時に CNI Plugin から呼び出し）
POST http://10.100.1.1:8080/api/containers
{
  "id": "abc123",
  "ip": "10.100.1.10",
  "hostname": "my-service",
  "ports": [80, 443],
  "hostId": 1,
  "createdAt": "2024-01-01T00:00:00Z"
}

# コンテナ一覧取得（他 Gateway からの同期用）
GET http://10.100.1.1:8080/api/containers
[
  {"id": "abc123", "ip": "10.100.1.10", "hostId": 1, "ttl": 300},
  {"id": "def456", "ip": "10.100.2.10", "hostId": 2, "ttl": 280}
]

# コンテナ削除（コンテナ停止時）
DELETE http://10.100.1.1:8080/api/containers/abc123
```

**同期タイミング:**
- 起動時: 他 Gateway から全コンテナ情報を取得
- 定期: 30秒ごとに差分同期
- イベント: コンテナ起動/停止時に即時通知

## 依存関係

- Phase 2: CNI Plugin 実装
- Stage 2: ホスト間トンネル構築

## リスク

- コンテナ情報の同期遅延により古い情報でルーティングされる
  - 対策: TTL の設定、ヘルスチェックの実装
- ホスト ID の重複による IP 衝突
  - 対策: ホスト追加手順に ID 確認を含める

## 次のステップ

Stage 3 完了後は [Stage 4: Graceful Escalation 実装](./stage-4-graceful-escalation.md) に進み、P2P 経路確立とフォールバック機構を実装する。
