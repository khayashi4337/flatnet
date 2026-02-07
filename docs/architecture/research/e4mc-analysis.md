# e4mc アーキテクチャ調査

調査日: 2025-02-07
対象: https://github.com/vgskye/e4mc-minecraft-architectury

## 概要

e4mc は Minecraft の LAN サーバーを NAT 越えで公開する MOD。
QUIC リレーと iroh P2P (Dialtone) を組み合わせたアーキテクチャ。

## 接続フェーズ

| Phase | プロトコル | 役割 | 詳細 |
|-------|-----------|------|------|
| Phase 0 | HTTP | シグナリング | ブローカー + DNS TXT でチケット取得 |
| Phase 1 | QUIC | 制御プレーン | リレー接続（常時維持） |
| Phase 2 | iroh | NAT越え | バックグラウンドで STUN + ホールパンチ |
| Phase 3 | Dialtone | データプレーン | P2P 成功時、DialtoneChannel に差し替え |

## アーキテクチャ図

```
[Minecraft Client]
       │
       ├── Phase 0: HTTP ──→ [Broker] チケット取得
       │                      [DNS TXT] Resolver発見
       │
       ├── Phase 1: QUIC ──→ [Relay Server] 制御メッセージ
       │                      (常時維持)
       │
       └── Phase 2-3: iroh ──→ [Host] P2P直接通信
                               (成功時のみ)
```

## 重要な発見

### 1. 「昇格」ではなく「並行稼働」
- QUIC リレー（制御プレーン）は P2P 確立後も維持される
- データプレーンのみが P2P に切り替わる
- 制御メッセージ（チケット配布等）は引き続きリレー経由

### 2. フォールバックなし
- P2P (Dialtone) 接続が失敗した場合、接続自体が失敗
- リレー経由のデータ転送へのフォールバックは存在しない
- これは e4mc の弱点

### 3. クライアント側に iroh 必須
- iroh-java (JNI ネイティブライブラリ) がクライアント側にも必要
- 両方のプレイヤーに MOD インストールが必要

## Flatnet への示唆

### マッピング

| e4mc | Flatnet |
|------|---------|
| HTTP ブローカー | OpenResty Gateway |
| QUIC リレー | OpenResty Gateway |
| iroh (クライアント側) | 不要（Gateway がカプセル化）|
| iroh (サーバー側) | CNI Plugin + Daemon |

### Flatnet の優位性

1. **クライアント要件の簡素化**
   - e4mc: iroh ネイティブライブラリ必須
   - Flatnet: HTTP のみ（ブラウザで完結）

2. **フォールバック維持**
   - e4mc: P2P 失敗 = 接続失敗
   - Flatnet: Gateway 経由の経路を常に維持可能

3. **既存インフラ活用**
   - e4mc: 専用 QUIC リレーが必要
   - Flatnet: OpenResty（一般的な HTTP インフラ）

## 参考コード

主要ファイル:
- `QuiclimeSession.java` - QUIC リレー接続、制御メッセージ
- `DialtoneChannel.java` - P2P 接続（クライアント側）
- `DialtoneServerChannel.java` - P2P 接続（サーバー側）
- `ServerNameResolverMixin.java` - DNS TXT + HTTP チケット取得
- `ConnectionMixin.java` - TCP → Dialtone チャネル差し替え

ソースコード: `vendor/reference/e4mc/` (git 管理外)
