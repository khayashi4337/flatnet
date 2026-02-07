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

**重要:** Podman v4 以降はデフォルトで netavark を使用。CNI を使うには設定が必要:
```bash
# 現在のバックエンド確認
podman info --format '{{.Host.NetworkBackend}}'

# CNI に切り替え
# /etc/containers/containers.conf
[network]
network_backend = "cni"
```

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

**完了条件:**
- [ ] CNI 仕様の要点が `docs/architecture/research/cni-spec.md` にまとまっている
- [ ] 入出力の JSON サンプルが整理されている

---

### Sub-stage 1.2: Podman CNI 調査

**内容:**
- Podman のネットワーク設定を確認（`podman network ls`）
- デフォルトの bridge ネットワークの動作確認
- CNI 設定ファイルの場所と形式を確認
- `podman network create --driver` のオプションを調査

**完了条件:**
- [ ] Podman が CNI プラグインを呼び出す流れを理解
- [ ] カスタム CNI ネットワークの作成方法が分かる
- [ ] 調査結果が `docs/architecture/research/podman-cni.md` にまとまっている

---

### Sub-stage 1.3: Rust 開発環境構築

**内容:**
- rustup インストール（未導入の場合）
- stable toolchain の設定
- 必要なクレートの調査と選定
- プロジェクト構造の設計

**完了条件:**
- [ ] `rustc --version` が動作する
- [ ] `cargo new` でプロジェクトが作成できる
- [ ] 使用クレート一覧が決定している

---

### Sub-stage 1.4: プロジェクト初期化

**内容:**
- `src/flatnet-cni/` ディレクトリ作成
- `Cargo.toml` の初期設定
- 基本的なプロジェクト構造の作成
- CI 用の設定ファイル（将来用）

**完了条件:**
- [ ] `cargo build` が成功する
- [ ] `cargo test` が実行できる（テストが0件でもOK）
- [ ] プロジェクト構造が決定している

---

## 成果物

1. `docs/architecture/research/cni-spec.md` - CNI 仕様まとめ
2. `docs/architecture/research/podman-cni.md` - Podman CNI 調査結果
3. `src/flatnet-cni/` - Rust プロジェクトの初期構造
4. `src/flatnet-cni/Cargo.toml` - 依存関係定義

## 完了条件

- [ ] CNI 仕様の主要概念（ADD/DEL/CHECK、入出力形式）を説明できる
- [ ] Podman が CNI プラグインを呼び出す仕組みを説明できる
- [ ] `cargo build` でプロジェクトがビルドできる
- [ ] 次の Stage（最小プラグイン実装）に必要な知識が揃っている

## 次の Stage への引き継ぎ事項

- CNI 仕様の要点まとめドキュメント
- Podman CNI 調査結果ドキュメント
- 初期化済み Rust プロジェクト構造
- 選定済みクレート一覧

## 参考リンク

- [CNI Spec 1.0.0](https://github.com/containernetworking/cni/blob/spec-v1.0.0/SPEC.md)
- [Podman Networking](https://docs.podman.io/en/latest/markdown/podman-network.1.html)
- [Rust Book](https://doc.rust-lang.org/book/)
