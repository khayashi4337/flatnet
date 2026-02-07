# Phase 1: 基盤構築

## ゴール
最小構成でFlatnet CNIプラグインが動作し、Podmanコンテナ間の通信ができる状態を作る。

## Phase 1 完了条件
- [ ] Podman で起動した2つのコンテナが Flatnet 経由で相互に ping できる
- [ ] コンテナの起動・停止時に CNI プラグインが正しく呼ばれ、リソースがリークしない
- [ ] Forgejo + Runner が Flatnet 上で動作し、CI ジョブが実行できる

---

## Stages

### Stage 1: CNIプラグインのスケルトン

**概要**
- Rust で最小限のCNIプラグインを実装
- Podman から呼び出され、ADD/DEL/CHECK に応答できる
- まずは静的IPを返すだけのモック実装

**完了条件**
- [ ] `flatnet-cni` バイナリが `cargo build --release` でビルドできる
- [ ] CNI_COMMAND=ADD で呼び出すと、有効な CNI Result JSON を stdout に出力する
- [ ] CNI_COMMAND=DEL で呼び出すと、正常終了（exit 0）する
- [ ] CNI_COMMAND=CHECK で呼び出すと、正常終了（exit 0）する
- [ ] `podman run --network flatnet alpine echo hello` が成功する

---

### Stage 2: ネットワーク名前空間の操作

**概要**
- コンテナのネットワーク名前空間にインターフェースを作成
- IP割り当てとルーティング設定

**完了条件**
- [ ] コンテナ内に `flatnet0` インターフェースが作成される
- [ ] 指定したサブネット（例: 10.100.0.0/16）から IP が割り当てられる
- [ ] コンテナ内から `ip addr` で割り当てられた IP を確認できる
- [ ] コンテナ停止時にインターフェースが正しくクリーンアップされる

---

### Stage 3: メッシュトンネルの統合

**概要**
- オーバーレイネットワークのトンネル機能を組み込み
- コンテナ間の直接通信を実現

**完了条件**
- [ ] 同一ホスト上の2つのコンテナが Flatnet IP で相互に ping できる
- [ ] コンテナ間で TCP 通信ができる（例: nc でメッセージ送受信）
- [ ] 3つ以上のコンテナ間でも通信が成立する

---

### Stage 4: Forgejo統合テスト

**概要**
- Forgejo + Runner をFlatnet CNI上で起動
- git push → CI実行の一連のフローを検証

**完了条件**
- [ ] Forgejo が Flatnet 上で起動し、ブラウザからアクセスできる
- [ ] Forgejo Runner が Forgejo に接続し、オンライン状態になる
- [ ] テストリポジトリに push すると、Forgejo Actions ワークフローが実行される
- [ ] ワークフロー内で `echo "Hello from Flatnet"` が成功する
- [ ] 動作検証手順書が作成されている

---

## 成果物
- `flatnet-cni` バイナリ（Rust）
- Podman用ネットワーク設定ファイル（`/etc/cni/net.d/flatnet.conflist`）
- 動作検証手順書（`docs/phases/phase-1/verification.md`）
