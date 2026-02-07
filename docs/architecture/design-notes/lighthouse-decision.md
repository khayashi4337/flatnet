# 設計ノート: Lighthouse の方針

## 決定事項

**既存の Nebula Lighthouse を利用する。ただしクライアントには見せない。**

## 構成

```
[クライアント] ──HTTP──→ [OpenResty Gateway]
                              │
                              ├── Nebula Lighthouse（別プロセス）
                              │   └── ノード管理、NAT越え支援
                              │
                              └── WSL2 へプロキシ
```

## 理由

1. **実績のある実装を活用**: Nebula Lighthouse は NAT 越えの実績がある
2. **再発明を避ける**: Lua で Lighthouse 相当を実装するのは複雑
3. **カプセル化の原則を維持**: クライアントは HTTP のみ、Nebula の存在を知らない

## Phase との関係

| Phase | Lighthouse |
|-------|------------|
| Phase 1 | 不要（Gateway のみ）|
| Phase 2 | 不要（CNI + Gateway）|
| Phase 3 | **必要**（マルチホスト時に導入）|

## 実装方針（Phase 3）

- Nebula Lighthouse を Windows 上で起動
- OpenResty は Lighthouse に問い合わせてノード解決
- WSL2 側は Nebula クライアント相当の機能を持つ（CNI Plugin 内または別デーモン）
- 社内クライアントには一切見せない（HTTP で完結）

## 未決定事項

- [ ] Lighthouse の具体的な設定方法
- [ ] OpenResty ↔ Lighthouse の通信プロトコル
- [ ] WSL2 側の Nebula 連携方法
