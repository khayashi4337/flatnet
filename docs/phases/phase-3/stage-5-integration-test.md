# Stage 5: 統合テスト・ドキュメント

## 概要

Phase 3 全体の統合テストを実施し、マルチホスト環境での動作を検証する。また、運用に必要なドキュメントを整備する。

## ブランチ戦略

- ブランチ名: `phase3/stage-5-integration-test`
- マージ先: `master`

## インプット（前提条件）

- Stage 1-4 が完了している
- テスト用に 2台以上のホストが利用可能
- テスト用コンテナイメージが準備されている

## 目標

- Phase 3 全体の機能が正しく動作することを確認する
- エッジケースと障害シナリオをテストする
- 運用手順書を完成させる
- トラブルシューティングガイドを作成する

## ディレクトリ構成

```
[WSL2] /home/kh/prj/flatnet/
       ├── tests/
       │   └── integration/
       │       ├── phase3/
       │       │   ├── test_basic.sh        ← 基本機能テスト
       │       │   ├── test_escalation.sh   ← Graceful Escalation テスト
       │       │   ├── test_failure.sh      ← 障害シナリオテスト
       │       │   └── test_performance.sh  ← パフォーマンス測定
       │       └── fixtures/
       │           └── test-container/       ← テスト用コンテナ
       └── docs/
           └── operations/
               ├── setup-guide.md           ← セットアップ手順書
               ├── operations-guide.md      ← 運用手順書
               └── troubleshooting.md       ← トラブルシューティング
```

## 手段

- 統合テストシナリオの実行
- 障害注入テスト
- パフォーマンス測定
- ドキュメント作成

## Sub-stages

### Sub-stage 5.1: 基本機能テスト

**内容:**
- マルチホスト環境での基本的な動作確認
- 各コンポーネントの連携確認

**テストケース:**
1. **コンテナ起動テスト**
   - Host A でコンテナ起動 → Flatnet IP 割り当て確認
   - Host B でコンテナ起動 → IP 範囲が異なることを確認

2. **クロスホスト通信テスト**
   - Host A のコンテナから Host B のコンテナへ通信
   - 双方向で通信が成功することを確認

3. **Gateway 経由アクセステスト**
   - クライアントから Gateway A 経由で Host B のコンテナにアクセス
   - レスポンスが正しく返ることを確認

**完了条件:**
- [ ] 全ての基本テストケースが成功
- [ ] テスト結果が記録されている

### Sub-stage 5.2: Graceful Escalation テスト

**内容:**
- P2P 経路確立と切り替えの動作確認
- フォールバック機構の動作確認

**テストケース:**
1. **P2P 確立テスト**
   - 新規リクエスト → Gateway 経由で即応答
   - P2P 確立後 → 直接通信に切り替わることを確認

2. **フォールバックテスト**
   - P2P 通信中に Nebula を停止
   - 自動的に Gateway 経由にフォールバックすることを確認
   - クライアントにエラーが返らないことを確認

3. **復旧テスト**
   - フォールバック後に Nebula を再起動
   - P2P 経路が再確立されることを確認

**完了条件:**
- [ ] P2P 確立と切り替えが動作する
- [ ] フォールバックが自動的に行われる
- [ ] 復旧後に P2P が再確立される

### Sub-stage 5.3: 障害シナリオテスト

**内容:**
- 各種障害時の動作確認
- 回復性の検証

**テストケース:**
1. **Lighthouse 障害**
   - Lighthouse を停止
   - 既存接続が維持されることを確認
   - 新規ホスト追加ができないことを確認

2. **ホスト障害**
   - Host B を停止
   - Host A のコンテナは影響を受けないことを確認
   - Host B 宛てリクエストがタイムアウトすることを確認

3. **ネットワーク分断**
   - ホスト間の Nebula 通信を遮断
   - フォールバック動作を確認

4. **WSL2 再起動**
   - WSL2 を再起動
   - CNI Plugin が正しく再初期化されることを確認

**完了条件:**
- [ ] 各障害シナリオの動作が文書化されている
- [ ] 重大な問題がないことを確認

### Sub-stage 5.4: パフォーマンス測定

**内容:**
- 各経路でのレイテンシ測定
- スループット測定
- 切り替え時間の測定

**測定項目:**
1. **レイテンシ**
   - Gateway 経由: クライアント → Gateway → WSL2 → コンテナ
   - P2P 経由: コンテナ A → Nebula → コンテナ B

2. **スループット**
   - 大容量ファイル転送速度
   - 同時接続数の上限

3. **切り替え時間**
   - Gateway → P2P 切り替え時間
   - P2P → Gateway フォールバック時間

**完了条件:**
- [ ] 各測定項目の結果が記録されている
- [ ] ボトルネックが特定されている（あれば）

### Sub-stage 5.5: ドキュメント整備

**内容:**
- セットアップ手順書の完成
- 運用手順書の作成
- トラブルシューティングガイドの作成

**ドキュメント一覧:**
1. **セットアップ手順書**
   - Lighthouse のセットアップ
   - 新規ホストの追加手順
   - CNI Plugin のインストール

2. **運用手順書**
   - 日常的な運用タスク
   - 証明書の更新手順
   - ホストの追加・削除

3. **トラブルシューティングガイド**
   - よくある問題と解決方法
   - ログの確認方法
   - 障害時の対応フロー

**完了条件:**
- [ ] セットアップ手順書が完成
- [ ] 運用手順書が完成
- [ ] トラブルシューティングガイドが完成
- [ ] 別の担当者が手順書に従って環境構築できることを確認

## 成果物

| 種別 | パス | 説明 |
|------|------|------|
| テストスクリプト | `tests/integration/phase3/test_basic.sh` | 基本機能テスト |
| テストスクリプト | `tests/integration/phase3/test_escalation.sh` | Graceful Escalation テスト |
| テストスクリプト | `tests/integration/phase3/test_failure.sh` | 障害シナリオテスト |
| テストスクリプト | `tests/integration/phase3/test_performance.sh` | パフォーマンス測定 |
| ドキュメント | `docs/operations/setup-guide.md` | セットアップ手順書 |
| ドキュメント | `docs/operations/operations-guide.md` | 運用手順書 |
| ドキュメント | `docs/operations/troubleshooting.md` | トラブルシューティング |
| レポート | `docs/phases/phase-3/test-results.md` | テスト結果レポート |

## 完了条件

- [ ] 全ての統合テストが成功している
- [ ] 障害シナリオの動作が文書化されている
- [ ] パフォーマンス測定が完了している
- [ ] 運用ドキュメントが整備されている
- [ ] Phase 3 完了レビューが承認されている

## 技術メモ

### テスト環境構成

```
[テスト環境]
  Host A: Windows 11 + WSL2
    └── Container A1 (10.100.1.10)
    └── Container A2 (10.100.1.11)

  Host B: Windows 11 + WSL2
    └── Container B1 (10.100.2.10)
    └── Container B2 (10.100.2.11)

  Lighthouse: 10.100.0.1

  テストクライアント: 社内 LAN 上の PC
```

### テストツール

- **HTTP テスト**: curl, ab (Apache Bench), wrk
- **ネットワークテスト**: ping, iperf3, traceroute
- **障害注入**: tc (traffic control), iptables
- **ログ分析**: journalctl, grep

### 具体的なテストコマンド例

```bash
# クロスホスト通信テスト（Host A から Host B のコンテナへ）
curl -v http://10.100.2.10:80/

# レイテンシ測定
ping -c 100 10.100.2.10 | tail -1

# スループット測定（iperf3 サーバーを Host B で起動済み）
iperf3 -c 10.100.2.10 -t 30

# P2P 経路の確認（Nebula ログ）
grep "Hole punch" /var/log/nebula.log

# Gateway 経由のアクセステスト
curl -H "Host: my-service.flatnet" http://gateway-a/

# 障害注入（Nebula 通信を一時的に遮断）
sudo iptables -A OUTPUT -p udp --dport 4242 -j DROP
# テスト後に解除
sudo iptables -D OUTPUT -p udp --dport 4242 -j DROP

# 負荷テスト（100並列、1000リクエスト）
ab -n 1000 -c 100 http://gateway-a/api/health
```

### チェックリストテンプレート

```markdown
## テスト実行記録

日時: YYYY-MM-DD HH:MM
実行者:

### 基本機能テスト
- [ ] コンテナ起動テスト: PASS / FAIL
- [ ] クロスホスト通信テスト: PASS / FAIL
- [ ] Gateway 経由アクセステスト: PASS / FAIL

### Graceful Escalation テスト
- [ ] P2P 確立テスト: PASS / FAIL
- [ ] フォールバックテスト: PASS / FAIL
- [ ] 復旧テスト: PASS / FAIL

### 備考
（問題があった場合の詳細）
```

## 依存関係

- Stage 1-4 全て

## リスク

- テスト環境と本番環境の差異による問題
  - 対策: 可能な限り本番に近い環境でテスト
- ドキュメントの陳腐化
  - 対策: バージョン管理、定期的なレビュー

## Phase 3 完了後

Stage 5 完了で Phase 3 は完了。[Phase 4: 本番運用準備](../phase-4/README.md) に進む。

**Phase 4 で対応する項目:**
- リモートメンバー対応（インターネット越え）
- 監視・ログ基盤
- セキュリティ強化（認証・認可の高度化）
- Lighthouse の冗長化
