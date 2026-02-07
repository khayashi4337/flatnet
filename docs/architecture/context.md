# Flatnet - System Context (C4 Level 1)

## 概要
Flatnet は、NATの多段構成を意識せずにコンテナへ直接到達できるネットワーク層を提供する。

## 解決する問題
- WSL2 + Podman環境では NAT が3段（社内LAN → Windows → WSL2 → コンテナ）になる
- 利用者（開発メンバー）にVPNクライアントのインストールを強要したくない
- サーバー管理者がWSL2内のネットワーク構成をシンプルに保ちたい

## システム全体像
```
[社内メンバー] --HTTP--> [Host Windows: OpenResty + Lighthouse]
                              |
                         [WSL2: Podman + Flatnet CNI]
                              |
                     +--------+--------+
                     |                 |
              [Forgejo Pod]    [Forgejo Runner Pod]
                                       |
                               [CI/CD: Build, Test, etc.]
```

## アクター
- **社内メンバー (Member1)**: ブラウザのみでForegejoにアクセス。追加インストール不要
- **リモートメンバー (Member2)**: 任意のVPN経由でアクセス（将来対応）
- **サーバー管理者**: Flatnetのセットアップと運用を行う

## 主要コンポーネント
1. **Flatnet CNI Plugin** - Podmanコンテナに直接到達可能なネットワークを提供するCNIプラグイン（Rust製）
2. **Flatnet Gateway** - OpenResty + Lua によるリバースプロキシ兼エントリーポイント
3. **Flatnet Lighthouse** - ノード間の経路情報を管理（内部的にメッシュVPN技術を活用）

## 設計原則
- 利用者にネットワーク層の複雑さを漏らさない
- NATの存在を前提としない（flat network）
- サーバー側で全てのNAT問題を吸収する
