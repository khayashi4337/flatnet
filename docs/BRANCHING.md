# ブランチ命名規則

## 命名規則

### フォーマット
`p{phase}-s{stage}-{substage}-{slug}`

例: `p1-s1-1-openresty-install`

### ルール
- phase: 1桁の数字
- stage: 1桁の数字
- substage: 1桁の数字
- slug: 小文字英数字とハイフン、2-4単語程度

## ブランチ一覧

### Phase 1: Gateway 基盤

#### Stage 1: OpenResty セットアップ
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 1.1 | openresty-install | p1-s1-1-openresty-install | OpenResty インストール |
| 1.2 | basic-config | p1-s1-2-basic-config | 基本設定 |
| 1.3 | firewall-setup | p1-s1-3-firewall-setup | Windows Firewall 設定 |
| 1.4 | deploy-script | p1-s1-4-deploy-script | デプロイスクリプト作成 |
| 1.5 | service-setup | p1-s1-5-service-setup | サービス化（オプション） |

#### Stage 2: WSL2 プロキシ設定
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 2.1 | wsl2-ip-method | p1-s2-1-wsl2-ip-method | WSL2 IP 取得方法の確立 |
| 2.2 | static-proxy | p1-s2-2-static-proxy | 静的プロキシ設定 |
| 2.3 | ip-update-script | p1-s2-3-ip-update-script | IP 更新スクリプト |
| 2.4 | proxy-headers | p1-s2-4-proxy-headers | プロキシヘッダーの調整 |

#### Stage 3: Forgejo 統合
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 3.1 | forgejo-container | p1-s3-1-forgejo-container | Forgejo コンテナ準備 |
| 3.2 | forgejo-init | p1-s3-2-forgejo-init | Forgejo 初期設定 |
| 3.3 | openresty-link | p1-s3-3-openresty-link | OpenResty 連携 |
| 3.4 | git-ops-test | p1-s3-4-git-ops-test | Git 操作確認 |
| 3.5 | podman-autostart | p1-s3-5-podman-autostart | Podman 自動起動設定 |

#### Stage 4: ドキュメント整備
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 4.1 | setup-guide | p1-s4-1-setup-guide | セットアップ手順書 |
| 4.2 | troubleshoot-guide | p1-s4-2-troubleshoot-guide | トラブルシューティングガイド |
| 4.3 | ops-guide | p1-s4-3-ops-guide | 運用ガイド |
| 4.4 | validation-test | p1-s4-4-validation-test | 検証テスト |

---

### Phase 2: CNI Plugin

#### Stage 1: CNI 仕様理解と開発環境
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 1.1 | cni-spec-research | p2-s1-1-cni-spec-research | CNI 仕様調査 |
| 1.2 | podman-cni-research | p2-s1-2-podman-cni-research | Podman CNI 調査 |
| 1.3 | rust-env-setup | p2-s1-3-rust-env-setup | Rust 開発環境構築 |
| 1.4 | project-init | p2-s1-4-project-init | プロジェクト初期化 |

#### Stage 2: 最小 CNI プラグイン実装
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 2.1 | cli-foundation | p2-s2-1-cli-foundation | CLI 基盤の実装 |
| 2.2 | input-parse | p2-s2-2-input-parse | 入力パース（Network Configuration） |
| 2.3 | output-format | p2-s2-3-output-format | 出力形式（CNI Result） |
| 2.4 | podman-integration | p2-s2-4-podman-integration | Podman 統合テスト（スタブ） |

#### Stage 3: ネットワーク設定
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 3.1 | netns-ops | p2-s3-1-netns-ops | Network Namespace 操作 |
| 3.2 | veth-create | p2-s3-2-veth-create | veth ペア作成 |
| 3.3 | bridge-setup | p2-s3-3-bridge-setup | ブリッジ設定 |
| 3.4 | ipam-impl | p2-s3-4-ipam-impl | IP アドレス割り当て（IPAM） |
| 3.5 | container-netconf | p2-s3-5-container-netconf | コンテナ側ネットワーク設定 |
| 3.6 | del-command | p2-s3-6-del-command | DEL コマンド実装 |

#### Stage 4: Podman 統合と Gateway 連携
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 4.1 | win-wsl-routing | p2-s4-1-win-wsl-routing | Windows-WSL2 ルーティング設定 |
| 4.2 | openresty-update | p2-s4-2-openresty-update | OpenResty 設定更新 |
| 4.3 | multi-container | p2-s4-3-multi-container | 複数コンテナ運用テスト |
| 4.4 | lifecycle-test | p2-s4-4-lifecycle-test | ライフサイクルテスト |
| 4.5 | error-handling | p2-s4-5-error-handling | エラーハンドリング強化 |
| 4.6 | docs-update | p2-s4-6-docs-update | ドキュメント整備 |

---

### Phase 3: マルチホスト

#### Stage 1: Nebula Lighthouse 導入
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 1.1 | nebula-ca-setup | p3-s1-1-nebula-ca-setup | Nebula バイナリ取得と CA 構築 |
| 1.2 | lighthouse-cert | p3-s1-2-lighthouse-cert | Lighthouse 証明書生成 |
| 1.3 | lighthouse-config | p3-s1-3-lighthouse-config | Lighthouse 設定と起動 |
| 1.4 | nebula-firewall | p3-s1-4-nebula-firewall | ファイアウォール設定 |
| 1.5 | host-a-register | p3-s1-5-host-a-register | 最初のホスト（Host A）登録 |
| 1.6 | nebula-service | p3-s1-6-nebula-service | サービス化（NSSM） |

#### Stage 2: ホスト間トンネル構築
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 2.1 | host-b-setup | p3-s2-1-host-b-setup | Host B 証明書生成と接続 |
| 2.2 | host-comm-test | p3-s2-2-host-comm-test | ホスト間通信確認 |
| 2.3 | wsl2-nebula-access | p3-s2-3-wsl2-nebula-access | WSL2 からの Nebula ネットワークアクセス |
| 2.4 | host-add-procedure | p3-s2-4-host-add-procedure | 追加ホストの接続手順確立 |

#### Stage 3: CNI Plugin マルチホスト拡張
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 3.1 | host-id-ip-range | p3-s3-1-host-id-ip-range | ホスト ID による IP 範囲分離 |
| 3.2 | cross-host-route | p3-s3-2-cross-host-route | クロスホストルーティング |
| 3.3 | container-registry | p3-s3-3-container-registry | コンテナ情報共有機構 |
| 3.4 | cross-host-proxy | p3-s3-4-cross-host-proxy | Gateway のクロスホストプロキシ |
| 3.5 | cni-multihost | p3-s3-5-cni-multihost | CNI Plugin のマルチホスト対応 |

#### Stage 4: Graceful Escalation 実装
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 4.1 | conn-state-mgmt | p3-s4-1-conn-state-mgmt | 接続状態管理 |
| 4.2 | p2p-background | p3-s4-2-p2p-background | P2P 経路確立のバックグラウンド処理 |
| 4.3 | route-switch | p3-s4-3-route-switch | ルーティング切り替え |
| 4.4 | health-fallback | p3-s4-4-health-fallback | ヘルスチェックとフォールバック |
| 4.5 | client-transparent | p3-s4-5-client-transparent | クライアント透過性の確認 |

#### Stage 5: 統合テスト・ドキュメント
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 5.1 | basic-func-test | p3-s5-1-basic-func-test | 基本機能テスト |
| 5.2 | escalation-test | p3-s5-2-escalation-test | Graceful Escalation テスト |
| 5.3 | failure-scenario | p3-s5-3-failure-scenario | 障害シナリオテスト |
| 5.4 | perf-measure | p3-s5-4-perf-measure | パフォーマンス測定 |
| 5.5 | docs-finalize | p3-s5-5-docs-finalize | ドキュメント整備 |

---

### Phase 4: 本番運用

#### Stage 1: 監視基盤構築
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 1.1 | prometheus-setup | p4-s1-1-prometheus-setup | Prometheus 構築 |
| 1.2 | gateway-metrics | p4-s1-2-gateway-metrics | Gateway メトリクス公開 |
| 1.3 | cni-metrics | p4-s1-3-cni-metrics | CNI Plugin メトリクス公開 |
| 1.4 | node-exporter | p4-s1-4-node-exporter | Node Exporter 追加 |
| 1.5 | grafana-dashboard | p4-s1-5-grafana-dashboard | Grafana ダッシュボード構築 |
| 1.6 | alert-setup | p4-s1-6-alert-setup | アラート設定 |

#### Stage 2: ログ収集・分析
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 2.1 | loki-setup | p4-s2-1-loki-setup | Loki 構築 |
| 2.2 | promtail-setup | p4-s2-2-promtail-setup | Promtail 構築 |
| 2.3 | grafana-log | p4-s2-3-grafana-log | Grafana ログ統合 |
| 2.4 | log-rotation | p4-s2-4-log-rotation | ログローテーション設定 |
| 2.5 | log-format | p4-s2-5-log-format | ログ出力形式の標準化 |

#### Stage 3: セキュリティ強化
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 3.1 | security-audit | p4-s3-1-security-audit | セキュリティ監査 |
| 3.2 | vuln-scan | p4-s3-2-vuln-scan | 脆弱性スキャン |
| 3.3 | vuln-fix | p4-s3-3-vuln-fix | 脆弱性対処 |
| 3.4 | access-control | p4-s3-4-access-control | アクセス制御強化 |
| 3.5 | tls-setup | p4-s3-5-tls-setup | TLS 設定 |
| 3.6 | security-policy | p4-s3-6-security-policy | セキュリティポリシー文書化 |

#### Stage 4: 運用手順書作成
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 4.1 | daily-ops-guide | p4-s4-1-daily-ops-guide | 日常運用手順書 |
| 4.2 | runbook | p4-s4-2-runbook | 障害対応手順書（ランブック） |
| 4.3 | backup-restore | p4-s4-3-backup-restore | バックアップ・リストア手順 |
| 4.4 | maintenance-guide | p4-s4-4-maintenance-guide | メンテナンス手順 |

#### Stage 5: 連続運用テスト
| Sub-stage | Slug | ブランチ名 | 説明 |
|-----------|------|-----------|------|
| 5.1 | test-plan | p4-s5-1-test-plan | テスト計画策定 |
| 5.2 | continuous-test | p4-s5-2-continuous-test | 連続運用テスト実施 |
| 5.3 | load-test | p4-s5-3-load-test | 負荷テスト |
| 5.4 | issue-fix | p4-s5-4-issue-fix | 問題対処 |
| 5.5 | test-report | p4-s5-5-test-report | 運用テストレポート作成 |
