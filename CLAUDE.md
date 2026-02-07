# Flatnet プロジェクトコンテキスト

## プロジェクト概要
WSL2 + Podman環境の多段NAT問題を解消するCNIプラグインとゲートウェイ。
利用者にVPNインストールを強要せず、サーバー側でNAT問題を吸収する設計。

## 設計判断（決定済み）
- 実装言語: Rust（メモリ安全性のため）
- 内部的にメッシュVPN技術（Nebula相当）を活用するが、外部にはNebulaの名前を露出しない
- 社内メンバーはブラウザのみ、リモートは任意VPN経由
- OpenResty(Nginx+Lua)がGateway兼Lighthouse
- Podman CNIプラグインとしてコンテナにフラットIPを割り当て
- C4モデルを意識した設計ドキュメント管理
- 計画粒度: phase > stage > sub-stage

## 構成
- docs/architecture/ : C4モデルベースの設計書
- docs/phases/ : 開発計画
- src/ : Rustソースコード

## 現在のフェーズ
Phase 1, Stage 1: CNIプラグインのスケルトン作成（これから着手）

## 技術的な前提
- WSL2 (Ubuntu 24.04) 上で開発
- Podman v4系（Netavarkがデフォルト）
- CNIプラグインはstdin/stdout/環境変数でPodmanとやり取り
