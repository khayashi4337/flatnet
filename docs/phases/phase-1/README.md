# Phase 1: 基盤構築

## ゴール
最小構成でFlatnet CNIプラグインが動作し、Podmanコンテナ間の通信ができる状態を作る。

## Stages

### Stage 1: CNIプラグインのスケルトン
- Rust で最小限のCNIプラグインを実装
- Podman から呼び出され、ADD/DEL/CHECK に応答できる
- まずは静的IPを返すだけのモック実装

### Stage 2: ネットワーク名前空間の操作
- コンテナのネットワーク名前空間にインターフェースを作成
- IP割り当てとルーティング設定

### Stage 3: メッシュトンネルの統合
- オーバーレイネットワークのトンネル機能を組み込み
- コンテナ間の直接通信を実現

### Stage 4: Forgejo統合テスト
- Forgejo + Runner をFlatnet CNI上で起動
- git push → CI実行の一連のフローを検証

## 成果物
- `flatnet-cni` バイナリ（Rust）
- Podman用ネットワーク設定ファイル
- 動作検証手順書
