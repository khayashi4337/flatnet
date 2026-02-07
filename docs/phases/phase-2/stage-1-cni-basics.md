# Stage 1: CNI仕様理解と開発環境

## 概要

CNI（Container Network Interface）仕様を理解し、Rust開発環境を整備する。この Stage は実装の土台となる知識とツールを準備するフェーズである。

## ブランチ戦略

- ブランチ名: `phase2/stage-1-cni-basics`
- マージ先: `master`

## インプット（前提条件）

- Phase 1 完了（Gateway が動作している状態）
- WSL2 Ubuntu 24.04 環境
- Podman v4 系がインストール済み
- 基本的な Rust の知識

**前提条件の確認コマンド:**
```bash
# WSL2 環境確認
cat /etc/os-release | grep VERSION

# Podman バージョン確認
podman --version
# 期待出力: podman version 4.x.x

# Gateway 動作確認（Phase 1）
curl http://localhost/health 2>/dev/null || echo "Gateway not running (OK if Stage 1-3)"
```

## 目標

1. CNI 仕様 1.0.0 の主要概念を理解する
2. Podman が CNI プラグインを呼び出す仕組みを理解する
3. Rust 開発環境を構築する
4. プロジェクト構造を決定する

## 手段

### CNI 仕様の調査

CNI 仕様書（https://github.com/containernetworking/cni/blob/spec-v1.0.0/SPEC.md）を読み、以下を整理:

1. プラグインの呼び出し方法（実行ファイル + 環境変数 + stdin）
2. 3つのオペレーション（ADD/DEL/CHECK）の役割
3. 入力形式（Network Configuration）と出力形式（Result）
4. エラーハンドリング方法

### Podman の CNI 連携調査

1. Podman のネットワークモード（CNI vs netavark）を確認
2. CNI 設定ファイルの配置場所（`/etc/cni/net.d/`）
3. プラグインバイナリの配置場所（`/opt/cni/bin/`）
4. 既存プラグイン（bridge, loopback等）の動作確認

**重要:** Podman v4 以降はデフォルトで netavark を使用。CNI を使うには設定が必要。

**rootful Podman の場合（推奨）:**
```bash
# 現在のバックエンド確認
sudo podman info --format '{{.Host.NetworkBackend}}'
# 期待出力: cni（netavark の場合は設定変更が必要）

# CNI に切り替え
sudo mkdir -p /etc/containers
sudo tee /etc/containers/containers.conf << 'EOF'
[network]
network_backend = "cni"
EOF

# 設定反映の確認
sudo podman system reset --force  # 注意: 既存コンテナ・イメージが削除される
sudo podman info --format '{{.Host.NetworkBackend}}'
```

**rootless Podman の場合:**
```bash
# rootless Podman のバックエンド確認
podman info --format '{{.Host.NetworkBackend}}'

# rootless 用設定
mkdir -p ~/.config/containers
tee ~/.config/containers/containers.conf << 'EOF'
[network]
network_backend = "cni"
EOF

podman system reset --force
podman info --format '{{.Host.NetworkBackend}}'
```

**注意:** CNI プラグインによるブリッジ作成や veth 操作には root 権限が必要なため、Phase 2 では **rootful Podman（sudo podman）を使用することを推奨**。

### Rust 開発環境構築

1. rustup のインストール・更新
2. 必要なターゲット追加（`x86_64-unknown-linux-gnu`）
3. 開発ツールのインストール（cargo-watch, rust-analyzer等）

---

## Sub-stages

### Sub-stage 1.1: CNI 仕様調査

**内容:**
- CNI Spec 1.0.0 ドキュメントを精読
- ADD/DEL/CHECK の入出力形式をまとめる
- Network Configuration の構造を理解
- エラー形式（`{"code": N, "msg": "..."}`)を確認

**主要な CNI 概念:**

| 概念 | 説明 |
|------|------|
| Network Configuration | プラグインへの設定（JSON、stdin経由） |
| CNI_COMMAND | 実行するオペレーション（ADD/DEL/CHECK/VERSION） |
| CNI_CONTAINERID | コンテナの一意識別子 |
| CNI_NETNS | コンテナの network namespace パス |
| CNI_IFNAME | 作成するインターフェース名（通常 eth0） |
| Result | プラグインの出力（成功時は stdout、失敗時は stderr） |

**完了条件:**
- [ ] CNI 仕様の要点が `docs/architecture/research/cni-spec.md` にまとまっている
  ```bash
  # ドキュメント存在確認
  test -f docs/architecture/research/cni-spec.md && echo "OK"
  ```
- [ ] 入出力の JSON サンプルが整理されている

---

### Sub-stage 1.2: Podman CNI 調査

**内容:**
- Podman のネットワーク設定を確認（`podman network ls`）
- デフォルトの bridge ネットワークの動作確認
- CNI 設定ファイルの場所と形式を確認
- `podman network create --driver` のオプションを調査

**調査コマンド:**
```bash
# ネットワーク一覧
podman network ls

# デフォルトネットワークの詳細
podman network inspect podman

# CNI 設定ファイルの確認
ls -la /etc/cni/net.d/
cat /etc/cni/net.d/*.conflist 2>/dev/null || echo "No conflist files"

# CNI プラグインバイナリの確認
ls -la /opt/cni/bin/ 2>/dev/null || ls -la /usr/lib/cni/ 2>/dev/null

# CNI プラグインのパス確認
podman info --format '{{.Host.CniPath}}'
```

**完了条件:**
- [ ] Podman が CNI プラグインを呼び出す流れを理解
  ```bash
  # CNI バックエンドが有効か確認
  podman info --format '{{.Host.NetworkBackend}}' | grep -q cni && echo "OK"
  ```
- [ ] カスタム CNI ネットワークの作成方法が分かる
- [ ] 調査結果が `docs/architecture/research/podman-cni.md` にまとまっている
  ```bash
  test -f docs/architecture/research/podman-cni.md && echo "OK"
  ```

---

### Sub-stage 1.3: Rust 開発環境構築

**内容:**
- rustup インストール（未導入の場合）
- stable toolchain の設定
- 必要なクレートの調査と選定
- プロジェクト構造の設計

**手順:**
```bash
# rustup インストール（未導入の場合）
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# stable toolchain 確認・更新
rustup default stable
rustup update

# 開発ツールインストール
cargo install cargo-watch
cargo install cargo-edit

# ビルドに必要なシステム依存（Ubuntu）
sudo apt-get update
sudo apt-get install -y build-essential pkg-config
```

**選定クレート一覧:**

| クレート | 用途 | バージョン目安 |
|---------|------|---------------|
| `serde` | シリアライズ/デシリアライズ | 1.x |
| `serde_json` | JSON 処理 | 1.x |
| `nix` | Linux システムコール | 0.27+ |
| `rtnetlink` | netlink 操作 | 0.13+ |
| `ipnetwork` | IP アドレス操作 | 0.20+ |
| `thiserror` | エラー型定義 | 1.x |
| `tokio` | 非同期ランタイム（rtnetlink 用） | 1.x |
| `fs2` | ファイルロック（IPAM 用） | 0.4+ |

**完了条件:**
- [ ] `rustc --version` が動作する
  ```bash
  rustc --version
  # 期待出力: rustc 1.7x.x (xxxx)
  ```
- [ ] `cargo new` でプロジェクトが作成できる
  ```bash
  cargo new --bin /tmp/test-project && rm -rf /tmp/test-project && echo "OK"
  ```
- [ ] 使用クレート一覧が決定している

---

### Sub-stage 1.4: プロジェクト初期化

**内容:**
- `src/flatnet-cni/` ディレクトリ作成
- `Cargo.toml` の初期設定
- 基本的なプロジェクト構造の作成
- CI 用の設定ファイル（将来用）

**手順:**
```bash
# プロジェクトディレクトリに移動
cd /home/kh/prj/flatnet

# Rust プロジェクト作成
mkdir -p src
cargo new --bin src/flatnet-cni
cd src/flatnet-cni

# Cargo.toml に依存関係を追加
cat >> Cargo.toml << 'EOF'

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "1"

# Linux 固有（後で追加）
# nix = { version = "0.27", features = ["net", "sched"] }
# rtnetlink = "0.13"
# tokio = { version = "1", features = ["rt", "macros"] }
# ipnetwork = "0.20"
# fs2 = "0.4"
EOF
```

**プロジェクト構造:**
```
src/flatnet-cni/
├── Cargo.toml
├── src/
│   ├── main.rs           # エントリーポイント
│   ├── lib.rs            # ライブラリルート（オプション）
│   ├── config.rs         # 設定パース
│   ├── result.rs         # CNI Result 出力
│   └── error.rs          # エラー型
└── tests/                # 統合テスト（後で追加）
```

**完了条件:**
- [ ] `cargo build` が成功する
  ```bash
  cd /home/kh/prj/flatnet/src/flatnet-cni
  cargo build 2>&1 | tail -1
  # 期待出力: Finished ... target(s) in ...
  ```
- [ ] `cargo test` が実行できる（テストが0件でもOK）
  ```bash
  cargo test
  # 期待出力: running 0 tests ... test result: ok
  ```
- [ ] プロジェクト構造が決定している
  ```bash
  ls -la src/flatnet-cni/src/
  ```

---

## 成果物

1. `docs/architecture/research/cni-spec.md` - CNI 仕様まとめ
2. `docs/architecture/research/podman-cni.md` - Podman CNI 調査結果
3. `src/flatnet-cni/` - Rust プロジェクトの初期構造
4. `src/flatnet-cni/Cargo.toml` - 依存関係定義

## 完了条件

| 条件 | 確認方法 |
|------|----------|
| CNI 仕様の主要概念を説明できる | `docs/architecture/research/cni-spec.md` が存在 |
| Podman CNI 連携を理解している | `docs/architecture/research/podman-cni.md` が存在 |
| Rust 環境が構築されている | `rustc --version` が動作 |
| プロジェクトがビルドできる | `cargo build` が成功 |

**一括確認スクリプト:**
```bash
#!/bin/bash
echo "=== Stage 1 完了チェック ==="

# ドキュメント確認
test -f docs/architecture/research/cni-spec.md && echo "[OK] cni-spec.md" || echo "[NG] cni-spec.md"
test -f docs/architecture/research/podman-cni.md && echo "[OK] podman-cni.md" || echo "[NG] podman-cni.md"

# Rust 環境
rustc --version >/dev/null 2>&1 && echo "[OK] rustc" || echo "[NG] rustc"

# プロジェクトビルド
cd /home/kh/prj/flatnet/src/flatnet-cni
cargo build --quiet 2>/dev/null && echo "[OK] cargo build" || echo "[NG] cargo build"

# Podman CNI バックエンド
podman info --format '{{.Host.NetworkBackend}}' 2>/dev/null | grep -q cni && echo "[OK] Podman CNI backend" || echo "[NG] Podman CNI backend"
```

## トラブルシューティング

### rustup インストールが失敗する

**症状:** curl でダウンロードできない

**対処:**
```bash
# プロキシ環境の場合
export https_proxy=http://proxy.example.com:8080
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Podman が netavark のまま

**症状:** `podman info` で `NetworkBackend: netavark` と表示される

**対処:**
```bash
# 設定ファイルを確認
cat /etc/containers/containers.conf

# rootless Podman の場合はユーザー設定も確認
cat ~/.config/containers/containers.conf

# 設定後は Podman をリセット（注意: コンテナ・イメージが削除される）
podman system reset --force
```

### cargo build で依存関係エラー

**症状:** nix や rtnetlink クレートのビルドエラー

**対処:**
```bash
# ビルド依存のインストール
sudo apt-get install -y build-essential pkg-config libssl-dev

# Linux ヘッダー（WSL2 で必要な場合）
sudo apt-get install -y linux-headers-generic
```

## 次の Stage への引き継ぎ事項

- CNI 仕様の要点まとめドキュメント
- Podman CNI 調査結果ドキュメント
- 初期化済み Rust プロジェクト構造
- 選定済みクレート一覧

## 参考リンク

- [CNI Spec 1.0.0](https://github.com/containernetworking/cni/blob/spec-v1.0.0/SPEC.md)
- [Podman Networking](https://docs.podman.io/en/latest/markdown/podman-network.1.html)
- [Rust Book](https://doc.rust-lang.org/book/)
- [nix crate](https://docs.rs/nix/)
- [rtnetlink crate](https://docs.rs/rtnetlink/)
