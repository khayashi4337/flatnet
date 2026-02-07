# Flatnet - Container Diagram (C4 Level 2)

## Host Windows 層

### Flatnet Gateway (OpenResty)
- Nginx + Lua ベースのリバースプロキシ
- 社内メンバーからのHTTPリクエストを受け付ける唯一のエントリーポイント
- WSL2内のコンテナへFlatnetネットワーク経由でプロキシ

### Flatnet Lighthouse
- ネットワーク内のノード経路情報を管理
- 各コンテナのFlatnet IPを把握し、到達性を保証

## WSL2 層

### Podman + Flatnet CNI
- コンテナ起動時にFlatnet CNIプラグインが呼ばれる
- 各コンテナにFlatnet IPを割り当て
- コンテナ間通信はFlatnetオーバーレイで直接通信（NATを経由しない）

### Pod: Forgejo
- Gitホスティングサービス
- Flatnet IP で Gateway から直接到達可能

### Pod: Forgejo Runner
- Forgejo Actions の実行環境
- PinP (Podman in Podman) でCI/CDジョブを実行
- ビルド、テスト等の処理を担当
