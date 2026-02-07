# Stage 3: セキュリティ強化

## 概要

Flatnet システム全体のセキュリティを監査し、脆弱性を対処する。アクセス制御を強化し、セキュリティポリシーを文書化して、本番運用に適した状態にする。

## ブランチ戦略

- ブランチ名: `phase4/stage-3-security`
- マージ先: `master`

## インプット（前提条件）

- Stage 1-2（監視・ログ基盤）が完了している
- Gateway と CNI Plugin が稼働している
- セキュリティ監査を実施するための権限がある

## 目標

- セキュリティ監査を実施し、脆弱性を特定する
- 重大な脆弱性を対処する
- アクセス制御ポリシーを策定・適用する
- セキュリティ関連ドキュメントを整備する

## 手段

- 脆弱性スキャンツールによる自動スキャン
- 手動セキュリティレビュー
- ネットワークセグメンテーションの確認
- アクセス制御の実装と検証

---

## Sub-stages

### Sub-stage 3.1: セキュリティ監査

**内容:**
- 各コンポーネントの脆弱性スキャン
- ネットワーク構成の確認
- 認証・認可の確認
- 機密情報の取り扱い確認

**監査チェックリスト:**

ネットワーク:
- [ ] 不要なポートが開放されていないか
- [ ] ファイアウォールルールが適切か
- [ ] 内部通信が適切にセグメント化されているか
- [ ] 外部からのアクセス経路が制限されているか

認証・認可:
- [ ] 管理インターフェースに認証があるか
- [ ] デフォルトパスワードが変更されているか
- [ ] 最小権限の原則が適用されているか

機密情報:
- [ ] 機密情報がログに出力されていないか
- [ ] 設定ファイルの権限が適切か
- [ ] シークレットが暗号化されているか

コンテナセキュリティ:
- [ ] コンテナイメージが最新か
- [ ] 不要な特権が付与されていないか
- [ ] rootless で実行されているか

**完了条件:**
- [ ] 監査チェックリストが完了している
- [ ] 発見事項がリスト化されている
- [ ] 重要度（Critical/High/Medium/Low）が分類されている

---

### Sub-stage 3.2: 脆弱性スキャン

**内容:**
- Trivy によるコンテナイメージスキャン
- OpenResty/Nginx の既知脆弱性確認
- 依存ライブラリの脆弱性確認（Rust: cargo-audit）

**Trivy スキャン手順:**
```bash
# コンテナイメージのスキャン
trivy image flatnet/gateway:latest
trivy image flatnet/cni-plugin:latest

# 高・重大のみ表示
trivy image --severity HIGH,CRITICAL flatnet/gateway:latest

# JSON 出力でレポート作成
trivy image --format json --output trivy-report.json flatnet/gateway:latest
```

**Rust 依存関係スキャン:**
```bash
# cargo-audit のインストール
cargo install cargo-audit

# スキャン実行
cargo audit

# JSON 出力
cargo audit --json > audit-report.json
```

**スキャン対象:**

| 対象 | ツール | 頻度 |
|-----|--------|------|
| Gateway イメージ | Trivy | ビルド時、週次 |
| CNI Plugin イメージ | Trivy | ビルド時、週次 |
| Rust 依存関係 | cargo-audit | ビルド時、週次 |
| ベースイメージ | Trivy | 月次 |

**完了条件:**
- [ ] すべての対象に対してスキャンを実施
- [ ] Critical/High の脆弱性がリスト化されている
- [ ] スキャン結果がレポートとして保存されている

---

### Sub-stage 3.3: 脆弱性対処

**内容:**
- Critical/High 脆弱性の対処
- パッチ適用またはワークアラウンド
- 対処できない脆弱性のリスク評価

**対処優先度:**

| 重要度 | 対処期限 | 対応 |
|--------|---------|------|
| Critical | 24時間以内 | 即時対処またはサービス停止 |
| High | 1週間以内 | 計画的に対処 |
| Medium | 1ヶ月以内 | 次回リリースで対処 |
| Low | バックログ | 余裕があれば対処 |

**対処方法:**
1. パッケージ/ライブラリのアップデート
2. 設定変更による緩和
3. ネットワークレベルでのブロック
4. リスク受容（文書化必須）

**完了条件:**
- [ ] Critical 脆弱性がすべて対処されている
- [ ] High 脆弱性が対処または対処計画がある
- [ ] 対処状況がドキュメント化されている

---

### Sub-stage 3.4: アクセス制御強化

**内容:**
- Gateway への認証機能追加（オプション）
- 管理インターフェースの保護
- IP ベースのアクセス制限

**Gateway 認証オプション:**

オプション 1: Basic 認証
```nginx
location /admin {
    auth_basic "Admin Area";
    auth_basic_user_file /etc/nginx/.htpasswd;
    proxy_pass http://backend;
}
```

オプション 2: IP 制限
```nginx
location / {
    allow 192.168.1.0/24;  # 社内 LAN
    deny all;
    proxy_pass http://backend;
}
```

オプション 3: 両方を組み合わせ
```nginx
location / {
    satisfy any;
    allow 192.168.1.0/24;
    deny all;
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
    proxy_pass http://backend;
}
```

**管理インターフェースの保護:**
- Prometheus UI: IP 制限または認証プロキシ
- Grafana: ビルトイン認証を有効化
- Alertmanager UI: IP 制限

**完了条件:**
- [ ] アクセス制御方針が決定している
- [ ] 管理インターフェースが保護されている
- [ ] 不正アクセス試行がログに記録される

---

### Sub-stage 3.5: TLS 設定

**内容:**
- TLS 証明書の取得・設定
- HTTPS の有効化
- セキュアな TLS 設定

**TLS 設定例（OpenResty on Windows）:**
```nginx
server {
    listen 443 ssl http2;
    server_name flatnet.local;

    # Windows パスの場合
    ssl_certificate C:/openresty/conf/ssl/server.crt;
    ssl_certificate_key C:/openresty/conf/ssl/server.key;

    # Modern configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;

    # 注: OCSP Stapling は社内 CA 証明書では通常無効
    # ssl_stapling on;
    # ssl_stapling_verify on;
}
```

**注意:** OpenResty on Windows では、パスにフォワードスラッシュ（/）を使用するか、バックスラッシュをエスケープ（\\）する必要がある。

**証明書オプション:**
- 社内 CA による発行
- Let's Encrypt（外部公開時）
- 自己署名証明書（開発環境のみ）

**完了条件:**
- [ ] TLS 証明書が設定されている
- [ ] HTTPS でアクセスできる
- [ ] TLS 設定がベストプラクティスに従っている

---

### Sub-stage 3.6: セキュリティポリシー文書化

**内容:**
- セキュリティポリシーの策定
- インシデント対応手順の作成
- 定期セキュリティレビュー手順

**セキュリティポリシードキュメント:**

1. アクセス制御ポリシー
   - 誰がどのリソースにアクセスできるか
   - 認証方法
   - 権限管理手順

2. パッチ管理ポリシー
   - 脆弱性スキャン頻度
   - パッチ適用手順
   - 緊急パッチ対応

3. ログ・監査ポリシー
   - ログ保持期間
   - 監査ログの要件
   - ログレビュー頻度

4. インシデント対応手順
   - インシデントの定義
   - エスカレーションパス
   - 対応手順

**完了条件:**
- [ ] セキュリティポリシーが文書化されている
- [ ] インシデント対応手順が作成されている
- [ ] 関係者にポリシーが共有されている

---

## 成果物

- `docs/security/audit-report.md` - セキュリティ監査レポート
- `docs/security/vulnerability-report.md` - 脆弱性スキャン結果
- `docs/security/access-control-policy.md` - アクセス制御ポリシー
- `docs/security/incident-response.md` - インシデント対応手順
- TLS 証明書・設定ファイル
- 脆弱性スキャン CI/CD 設定

## 完了条件

- [ ] セキュリティ監査が完了し、レポートが作成されている
- [ ] Critical/High 脆弱性がすべて対処されている
- [ ] アクセス制御が適切に設定されている
- [ ] TLS が有効化されている
- [ ] セキュリティポリシーが文書化されている

## 参考情報

### セキュリティツール

| ツール | 用途 | インストール |
|--------|------|-------------|
| Trivy | コンテナスキャン | `brew install trivy` |
| cargo-audit | Rust 依存関係監査 | `cargo install cargo-audit` |
| nmap | ポートスキャン | `apt install nmap` |
| ssl-test | TLS 設定確認 | [SSL Labs](https://www.ssllabs.com/ssltest/) |

### OWASP セキュリティガイドライン

- [OWASP Docker Security](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [OWASP Nginx Security](https://cheatsheetseries.owasp.org/cheatsheets/Nginx_Security_Cheat_Sheet.html)

### コンプライアンス考慮事項

社内利用のため厳格なコンプライアンス要件はないが、以下を考慮:
- アクセスログの保持（監査目的）
- 最小権限の原則の適用
- 定期的なセキュリティレビュー
