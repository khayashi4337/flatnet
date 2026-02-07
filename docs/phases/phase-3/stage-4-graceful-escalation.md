# Stage 4: Graceful Escalation 実装

## 概要

Graceful Escalation パターンを実装する。初期接続は Gateway 経由で確実に行い、バックグラウンドで P2P 経路を確立して最適化する。P2P 失敗時は自動的に Gateway 経由にフォールバックする。

**設計原則:** 信頼性 > 最適化（詳細は [フォールバック戦略](../../architecture/design-notes/fallback-strategy.md) 参照）

## ブランチ戦略

- ブランチ名: `phase3/stage-4-graceful-escalation`
- マージ先: `master`

## インプット（前提条件）

- Stage 3 完了（CNI Plugin がマルチホスト対応）
- ホスト間トンネルが確立している
- Gateway 経由でのクロスホスト通信が動作している

## 目標

- 初期接続を Gateway 経由で確実に行う
- P2P 経路をバックグラウンドで確立する
- P2P 成功時は直接通信に切り替える
- P2P 失敗時は Gateway 経由にフォールバックする
- 切り替えがクライアントから透過的に行われる

## ディレクトリ構成

```
[Windows] F:\flatnet\
          └── openresty\
              └── lualib\
                  └── flatnet\
                      ├── registry.lua      ← Stage 3 で作成
                      ├── sync.lua          ← Stage 3 で作成
                      ├── escalation.lua    ← 接続状態管理
                      ├── healthcheck.lua   ← ヘルスチェック
                      └── routing.lua       ← ルーティング決定

[WSL2] /home/kh/prj/flatnet/
       └── config/
           └── openresty/
               └── conf.d/
                   └── escalation.conf  ← パラメータ設定
```

## 手段

- 接続状態管理機構の実装（Lua shared dict）
- P2P 経路確立のバックグラウンド処理（ngx.timer）
- ヘルスチェックとフォールバック機構
- メトリクス収集（オプション）

## Sub-stages

### Sub-stage 4.1: 接続状態管理

**内容:**
- 各コンテナへの接続状態を管理するモジュールを実装
- 状態遷移: `GATEWAY_ONLY` → `P2P_ACTIVE` → `GATEWAY_FALLBACK`
- 状態を Gateway 内で保持（Lua shared dict）

**状態定義:**
```
GATEWAY_ONLY     - Gateway 経由のみ（初期状態）
P2P_ATTEMPTING   - P2P 確立を試行中
P2P_ACTIVE       - P2P 経路がアクティブ
GATEWAY_FALLBACK - P2P 失敗後の Gateway フォールバック
```

**完了条件:**
- [ ] 接続状態の取得・更新 API が実装されている
  ```bash
  # 状態確認 API
  curl http://10.100.1.1:8080/api/escalation/state?ip=10.100.2.10
  # 期待: {"ip": "10.100.2.10", "state": "GATEWAY_ONLY"}
  ```
- [ ] 状態遷移が正しく動作する
- [ ] 状態がログに記録される
  ```powershell
  Get-Content F:\flatnet\logs\error.log | Select-String "escalation"
  ```

### Sub-stage 4.2: P2P 経路確立のバックグラウンド処理

**内容:**
- 新規コンテナ接続時に P2P 経路確立を非同期で開始
- Nebula のホールパンチング結果を監視
- 成功時に状態を `P2P_ACTIVE` に変更

**処理フロー:**
```
1. 新規リクエスト受信
2. 即座に Gateway 経由でプロキシ（待たない）
3. バックグラウンドで P2P 確立を試行
4. 成功したら状態を P2P_ACTIVE に変更
5. 次回以降のリクエストは P2P 経由
```

**完了条件:**
- [ ] バックグラウンドタスクが起動する
- [ ] P2P 確立成功を検知できる
- [ ] 状態が自動的に更新される

### Sub-stage 4.3: ルーティング切り替え

**内容:**
- 接続状態に基づいてルーティングを決定
- `P2P_ACTIVE` の場合は Nebula トンネル経由で直接通信
- それ以外は Gateway 経由

**ルーティング決定ロジック:**
```lua
function get_route(container_ip)
  local state = get_connection_state(container_ip)
  if state == "P2P_ACTIVE" then
    return {type = "p2p", target = container_ip}
  else
    return {type = "gateway", target = get_gateway_for(container_ip)}
  end
end
```

**完了条件:**
- [ ] 状態に基づいてルーティングが決定される
- [ ] P2P 経由の通信が実際に動作する
- [ ] Gateway 経由の通信も維持される

### Sub-stage 4.4: ヘルスチェックとフォールバック

**内容:**
- P2P 経路のヘルスチェックを定期実行
- 異常検知時に自動フォールバック
- フォールバック後の再試行ロジック

**ヘルスチェック基準:**
- レイテンシ閾値: 500ms 超過で警告、1000ms 超過でフォールバック
- パケットロス: 10% 超過でフォールバック
- 接続タイムアウト: 5秒応答なしでフォールバック

**推奨パラメータ:**
- ヘルスチェック間隔: 5秒
- 連続失敗でフォールバック: 3回
- 再試行バックオフ: 10秒 → 30秒 → 60秒 → 300秒（最大）
- フォールバック後の再試行開始: 30秒後

**完了条件:**
- [ ] ヘルスチェックが定期的に実行される（5秒間隔）
- [ ] 異常時に `GATEWAY_FALLBACK` に遷移する
- [ ] フォールバック時もリクエストが継続処理される
- [ ] 一定時間後に P2P 再試行が行われる
- [ ] パラメータが設定ファイルで調整可能

### Sub-stage 4.5: クライアント透過性の確認

**内容:**
- 切り替え時にクライアントから見て途切れがないことを確認
- HTTP セッションの維持
- WebSocket 等の長寿命接続の考慮

**テストケース:**
1. 通常リクエスト中に P2P 確立 → 次のリクエストは P2P 経由
2. P2P 通信中に障害発生 → 即座に Gateway フォールバック
3. フォールバック後に P2P 復旧 → 自動的に P2P に戻る

**テスト手順例:**

```bash
# 1. 初期リクエスト（Gateway 経由）
curl -v http://<Gateway-A>/container-b1/

# 2. 状態確認（P2P_ATTEMPTING または P2P_ACTIVE になるのを待つ）
watch -n 1 'curl -s http://10.100.1.1:8080/api/escalation/state?ip=10.100.2.10'

# 3. P2P 障害をシミュレート（Host B で Nebula を一時停止）
# Host B: Stop-Service Nebula

# 4. フォールバック確認（リクエストがエラーなく返る）
curl -v http://<Gateway-A>/container-b1/

# 5. 復旧（Host B で Nebula を再開）
# Host B: Start-Service Nebula

# 6. P2P 再確立を確認
watch -n 1 'curl -s http://10.100.1.1:8080/api/escalation/state?ip=10.100.2.10'
```

**完了条件:**
- [ ] 切り替え時にクライアントエラーが発生しない
- [ ] HTTP レスポンスが正常に返る（ステータス 200）
- [ ] 長寿命接続（該当する場合）が維持される

## 成果物

| 種別 | パス | 説明 |
|------|------|------|
| Lua モジュール | `F:\flatnet\openresty\lualib\flatnet\escalation.lua` | 接続状態管理 |
| Lua モジュール | `F:\flatnet\openresty\lualib\flatnet\healthcheck.lua` | ヘルスチェック |
| Lua モジュール | `F:\flatnet\openresty\lualib\flatnet\routing.lua` | ルーティング決定 |
| OpenResty 設定 | `F:\flatnet\config\openresty\conf.d\escalation.conf` | パラメータ設定 |
| テストスクリプト | `/home/kh/prj/flatnet/scripts/test-escalation.sh` | 切り替えテスト |

## 完了条件

- [ ] 初期接続が Gateway 経由で即座に成功する
- [ ] P2P 経路がバックグラウンドで確立される
- [ ] P2P 成功後は直接通信が行われる
- [ ] P2P 失敗時は自動的に Gateway にフォールバックする
- [ ] 切り替えがクライアントから透過的である

## 技術メモ

### 状態遷移図

```
[GATEWAY_ONLY] ←──────────────────────────┐
     │                                    │
     │ 接続開始                           │ P2P確立失敗/タイムアウト
     ▼                                    │
[P2P_ATTEMPTING] ─────────────────────────┘
     │
     │ P2P確立成功
     ▼
[P2P_ACTIVE]
     │
     │ ヘルスチェック失敗
     ▼
[GATEWAY_FALLBACK]
     │
     │ 一定時間経過（バックオフ付き）
     ▼
[P2P_ATTEMPTING] (再試行) → 成功: P2P_ACTIVE / 失敗: GATEWAY_ONLY
```

**ポイント:**
- P2P 確立に失敗しても Gateway 経由で通信は継続
- フォールバック後の再試行は指数バックオフで頻度を下げる
- 連続失敗時は再試行間隔を延長（例: 10秒 → 30秒 → 1分 → 5分）

### OpenResty 実装イメージ

```lua
-- 共有メモリで状態管理
local connection_states = ngx.shared.connection_states

-- 状態取得
function get_state(container_ip)
  return connection_states:get(container_ip) or "GATEWAY_ONLY"
end

-- P2P 確立バックグラウンドタスク
function attempt_p2p(container_ip)
  ngx.timer.at(0, function()
    set_state(container_ip, "P2P_ATTEMPTING")
    local success = try_p2p_connection(container_ip)
    if success then
      set_state(container_ip, "P2P_ACTIVE")
    else
      set_state(container_ip, "GATEWAY_ONLY")
    end
  end)
end

-- ヘルスチェック
function health_check_worker()
  -- 定期実行（ngx.timer.every で設定）
  for ip, state in pairs(active_p2p_connections) do
    if not check_health(ip) then
      set_state(ip, "GATEWAY_FALLBACK")
    end
  end
end
```

### P2P 確立の判定方法

Nebula のホールパンチ成功を検知する方法:
1. **ログ監視**: Nebula ログから `Hole punch established` を検知
2. **API 呼び出し**: Nebula の stats API（存在する場合）
3. **直接テスト**: P2P 経路での ping/HTTP テスト

## 依存関係

- Stage 3: CNI Plugin マルチホスト拡張

## 関連ドキュメント

- [フォールバック戦略](../../architecture/design-notes/fallback-strategy.md) - 設計方針と案の検討

## リスク

- P2P/Gateway 切り替え時にパケットロスが発生する可能性
  - 対策: 切り替え時に短時間両方の経路を使用
- ヘルスチェックの誤検知によるフラッピング
  - 対策: 複数回連続失敗で切り替え、バックオフ実装

## 次のステップ

Stage 4 完了後は [Stage 5: 統合テスト・ドキュメント](./stage-5-integration-test.md) に進み、Phase 3 全体の統合テストと運用ドキュメントを整備する。
