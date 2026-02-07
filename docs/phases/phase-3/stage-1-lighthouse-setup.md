# Stage 1: Nebula Lighthouse 導入

## 概要

Nebula Lighthouse をセットアップし、マルチホスト環境のノード管理基盤を構築する。Lighthouse は各ホストの位置情報を管理し、NAT 越えを支援する中央コーディネーターとして機能する。

## ブランチ戦略

- ブランチ名: `phase3/stage-1-lighthouse-setup`
- マージ先: `master`

## インプット（前提条件）

- Phase 2 が完了している（CNI Plugin が単一ホストで動作）
- Lighthouse を稼働させるサーバーまたはホストが決定している
- Nebula バイナリのダウンロードが可能
- Lighthouse 用の固定 IP または DNS 名が利用可能

## 目標

- Nebula Lighthouse を稼働させる
- 証明書インフラ（CA）を構築する
- 最初のホスト（Host A）を Lighthouse に登録する
- Lighthouse と Gateway の連携方式を設計する（実装は Stage 3 以降）

## 手段

- Nebula 公式バイナリのダウンロード
- nebula-cert による CA 証明書の生成
- Lighthouse 用 config.yaml の作成
- Windows サービスとしての登録（オプション）

## Sub-stages

### Sub-stage 1.1: Nebula バイナリ取得と CA 構築

**内容:**
- Nebula 公式リリースから Windows/Linux バイナリをダウンロード
  - 推奨バージョン: v1.9.x 以降（安定版）
  - ダウンロード先: https://github.com/slackhq/nebula/releases
- `nebula-cert ca` で CA 証明書を生成
- CA 秘密鍵の安全な保管場所を決定

**コマンド例:**
```bash
# CA 証明書の生成（有効期限 1年）
nebula-cert ca -name "Flatnet CA" -duration 8760h

# 生成されるファイル
# ca.crt - CA 公開証明書（各ホストに配布）
# ca.key - CA 秘密鍵（厳重に保管、証明書発行時のみ使用）
```

**完了条件:**
- [ ] `nebula` および `nebula-cert` バイナリが利用可能
- [ ] CA 証明書（`ca.crt`, `ca.key`）が生成されている
- [ ] CA 秘密鍵の保管場所が決定・文書化されている
- [ ] Nebula バージョンが記録されている

### Sub-stage 1.2: Lighthouse 証明書生成

**内容:**
- Lighthouse 用のノード証明書を生成
- Flatnet IP アドレス空間の設計（例: `10.100.0.0/16`）
- Lighthouse に `10.100.0.1` を割り当て

**完了条件:**
- [ ] Lighthouse 用証明書（`lighthouse.crt`, `lighthouse.key`）が生成されている
- [ ] Flatnet IP アドレス空間が決定・文書化されている

### Sub-stage 1.3: Lighthouse 設定と起動

**内容:**
- `config.yaml` の作成
  - `am_lighthouse: true`
  - `listen` ポートの設定（デフォルト: 4242/udp）
  - ファイアウォール設定（inbound/outbound ルール）
- Windows または Linux 上で Lighthouse を起動
- 起動確認とログ確認

**完了条件:**
- [ ] Lighthouse プロセスが起動している
- [ ] ログに `Lighthouse mode enabled` が出力されている
- [ ] 設定した UDP ポートでリッスンしている

### Sub-stage 1.4: ファイアウォール設定

**内容:**
- Windows Firewall で Nebula ポート（UDP 4242）を開放
- 必要に応じてルーター/VPN の設定

**完了条件:**
- [ ] 社内 LAN の別端末から Lighthouse の UDP ポートに到達可能
- [ ] `nebula-cert verify` で証明書の検証が成功する

### Sub-stage 1.5: 最初のホスト（Host A）登録

**内容:**
- Host A 用の証明書を生成（例: `10.100.1.1`）
- Host A に Nebula クライアントをインストール
- Lighthouse への接続確認

**完了条件:**
- [ ] Host A が Lighthouse に接続している（Lighthouse ログで確認）
- [ ] Host A の Nebula インターフェースに IP が割り当てられている

## 成果物

- Nebula バイナリ（Windows/Linux）
- CA 証明書一式（`ca.crt`, `ca.key`）
- Lighthouse 証明書一式
- Lighthouse 設定ファイル（`config.yaml`）
- ホスト証明書生成手順書
- IP アドレス空間設計書

## 完了条件

- [ ] Nebula Lighthouse が稼働している
- [ ] CA インフラが構築されている
- [ ] 最初のホスト（Host A）が Lighthouse に接続している
- [ ] 証明書生成手順が文書化されている

## 技術メモ

### Flatnet IP アドレス空間設計（案）

```
10.100.0.0/16 - Flatnet 全体
  10.100.0.0/24   - インフラ用
    10.100.0.1    - Lighthouse
    10.100.0.2-10 - 予約（将来の拡張用）

  10.100.X.0/24   - Host X（ホスト ID = X）用
    10.100.X.1    - Host X の Windows (Gateway/Nebula)
    10.100.X.2    - Host X の WSL2（オプション）
    10.100.X.10-254 - Host X 上のコンテナ用

例:
  10.100.1.0/24   - Host A（ホスト ID = 1）
    10.100.1.1    - Host A Gateway
    10.100.1.10   - Container A1
    10.100.1.11   - Container A2
  10.100.2.0/24   - Host B（ホスト ID = 2）
    10.100.2.1    - Host B Gateway
    10.100.2.10   - Container B1
```

### Lighthouse 設定例

```yaml
pki:
  ca: /etc/nebula/ca.crt
  cert: /etc/nebula/lighthouse.crt
  key: /etc/nebula/lighthouse.key

lighthouse:
  am_lighthouse: true

listen:
  host: 0.0.0.0
  port: 4242

firewall:
  outbound:
    - port: any
      proto: any
      host: any
  inbound:
    - port: any
      proto: any
      host: any
```

## 依存関係

- なし（Phase 3 の最初の Stage）

## 設計メモ: Lighthouse と Gateway の連携

Phase 3 では、Gateway が直接 Lighthouse に問い合わせるのではなく、以下の方式を採用:

1. **Nebula は純粋にトンネル提供**: ホスト間通信の暗号化と NAT 越え
2. **コンテナ情報は Gateway 間で同期**: Stage 3 で実装する HTTP API
3. **Lighthouse はノード管理に専念**: 新規ホストの参加、ホールパンチ支援

これにより、Nebula の設計を変更せずに Flatnet の機能を追加できる。

## リスク

- Lighthouse のダウンにより新規接続ができなくなる
  - 対策: 複数 Lighthouse の冗長化は Phase 4 で検討
