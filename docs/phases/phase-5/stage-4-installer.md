# Stage 4: インストーラーとドキュメント

## 概要

ワンライナーインストールスクリプトを提供し、ユーザードキュメントを整備する。CLI ツールを簡単に導入・アップグレードできるようにする。

## ブランチ戦略

- ブランチ名: `phase5/stage-4-installer`
- マージ先: `master`

## インプット（前提条件）

- Stage 1-3 が完了している
- CLI ツールがビルド可能

## 目標

- ワンライナーインストールスクリプトを提供する
- アップグレード機能を実装する
- ユーザーガイドを完成させる

## 手段

- シェルスクリプトによるインストーラー
- GitHub Releases からのダウンロード
- Markdown によるドキュメント整備

---

## Sub-stages

### Sub-stage 4.1: インストールスクリプト

**内容:**
- ワンライナーインストールスクリプトの作成
- プラットフォーム検出
- バイナリダウンロードと配置

**インストール方法:**
```bash
# ワンライナー
curl -fsSL https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh | bash

# または
wget -qO- https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh | bash
```

**スクリプト内容:**
```bash
#!/bin/bash
set -euo pipefail

REPO="khayashi4337/flatnet"
INSTALL_DIR="${FLATNET_INSTALL_DIR:-$HOME/.local/bin}"

# プラットフォーム検出
detect_platform() {
    local os arch
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)

    case "$arch" in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
    esac

    echo "${os}-${arch}"
}

# 最新バージョン取得
get_latest_version() {
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | \
        grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/'
}

# ダウンロードとインストール
install() {
    local platform version url
    platform=$(detect_platform)
    version=$(get_latest_version)

    echo "Installing flatnet v${version} for ${platform}..."

    url="https://github.com/${REPO}/releases/download/v${version}/flatnet-${platform}"

    mkdir -p "$INSTALL_DIR"
    curl -fsSL "$url" -o "${INSTALL_DIR}/flatnet"
    chmod +x "${INSTALL_DIR}/flatnet"

    echo "Installed to ${INSTALL_DIR}/flatnet"
    echo ""
    echo "Add to PATH if needed:"
    echo "  export PATH=\"\$PATH:${INSTALL_DIR}\""
}

install
```

**完了条件:**
- [ ] インストールスクリプトが動作する
- [ ] Linux x86_64 に対応している
- [ ] エラー処理が適切

---

### Sub-stage 4.2: アップグレードコマンド

**内容:**
- `flatnet upgrade` コマンドの実装
- バージョン確認
- 自動アップグレード

**出力例:**
```
$ flatnet upgrade

Current version: 0.1.0
Latest version:  0.2.0

Downloading flatnet v0.2.0...
[████████████████████████████████] 100%

Upgraded successfully!
Run 'flatnet --version' to confirm.
```

**オプション:**
```
flatnet upgrade              # 最新版にアップグレード
flatnet upgrade --check      # アップデート確認のみ
flatnet upgrade --version X  # 特定バージョンに
```

**完了条件:**
- [ ] `flatnet upgrade` が動作する
- [ ] `--check` オプションが動作する
- [ ] アップグレード後にバージョン確認できる

---

### Sub-stage 4.3: ユーザーガイド

**内容:**
- CLI ユーザーガイドの作成
- コマンドリファレンス
- トラブルシューティング

**ドキュメント構成:**
```
docs/cli/
├── README.md           # 概要とクイックスタート
├── installation.md     # インストール方法
├── commands/
│   ├── status.md       # status コマンド
│   ├── doctor.md       # doctor コマンド
│   ├── ps.md           # ps コマンド
│   └── logs.md         # logs コマンド
├── configuration.md    # 設定方法
└── troubleshooting.md  # トラブルシューティング
```

**README.md 内容:**
```markdown
# Flatnet CLI

Flatnet システムを管理するためのコマンドラインツール。

## クイックスタート

### インストール

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh | bash
\`\`\`

### 基本コマンド

\`\`\`bash
# システム状態を確認
flatnet status

# 問題を診断
flatnet doctor

# コンテナ一覧
flatnet ps

# ログを表示
flatnet logs gateway
\`\`\`

## コマンド一覧

| コマンド | 説明 |
|---------|------|
| status | システム全体の状態を表示 |
| doctor | システムを診断し問題を検出 |
| ps | コンテナ一覧を表示（Flatnet IP 付き） |
| logs | コンポーネントのログを表示 |
| upgrade | CLI を最新版にアップグレード |

詳細は各コマンドのドキュメントを参照。
```

**完了条件:**
- [ ] ユーザーガイドが完成している
- [ ] 各コマンドのドキュメントがある
- [ ] トラブルシューティングがある

---

### Sub-stage 4.4: GitHub Release 設定

**内容:**
- GitHub Actions によるリリース自動化
- バイナリビルドとアップロード
- リリースノート生成

**GitHub Actions ワークフロー:**
```yaml
# .github/workflows/release-cli.yml
name: Release CLI

on:
  push:
    tags:
      - 'cli-v*'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Rust
        uses: dtolnay/rust-action@stable

      - name: Build
        run: |
          cd src/flatnet-cli
          cargo build --release

      - name: Upload Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            target/release/flatnet
```

**完了条件:**
- [ ] GitHub Actions ワークフローが設定されている
- [ ] タグ push でリリースが作成される
- [ ] バイナリがリリースに添付される

---

## 成果物

| 種別 | パス | 説明 |
|------|------|------|
| スクリプト | `scripts/install-cli.sh` | インストールスクリプト |
| ソースコード | `src/flatnet-cli/src/commands/upgrade.rs` | upgrade コマンド |
| ドキュメント | `docs/cli/` | ユーザーガイド |
| CI/CD | `.github/workflows/release-cli.yml` | リリースワークフロー |

## 完了条件

- [ ] ワンライナーインストールが動作する
- [ ] `flatnet upgrade` が動作する
- [ ] ユーザーガイドが完成している
- [ ] GitHub Release が自動化されている

## 技術メモ

### セルフアップグレード

```rust
pub async fn upgrade(args: UpgradeArgs) -> Result<()> {
    let current = env!("CARGO_PKG_VERSION");
    let latest = get_latest_version().await?;

    if current == latest {
        println!("Already up to date (v{})", current);
        return Ok(());
    }

    if args.check {
        println!("Update available: v{} → v{}", current, latest);
        return Ok(());
    }

    // ダウンロードと置き換え
    let binary = download_binary(&latest).await?;
    let current_exe = std::env::current_exe()?;

    // 一時ファイルに書き込んでからリネーム（アトミック）
    let tmp = current_exe.with_extension("tmp");
    std::fs::write(&tmp, binary)?;
    std::fs::rename(&tmp, &current_exe)?;

    println!("Upgraded to v{}", latest);
    Ok(())
}
```

### クロスコンパイル

```bash
# Linux x86_64 向けビルド
cargo build --release --target x86_64-unknown-linux-gnu

# Linux ARM64 向けビルド（クロスコンパイル）
cargo build --release --target aarch64-unknown-linux-gnu
```

## 依存関係

- Stage 1-3 完了
- GitHub リポジトリへのアクセス

## リスク

- GitHub API レート制限
  - 対策: キャッシュ、認証トークン使用
- バイナリサイズが大きい
  - 対策: strip、LTO 最適化
