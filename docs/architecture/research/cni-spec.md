# CNI (Container Network Interface) 仕様まとめ

## 概要

CNI (Container Network Interface) は、Linux コンテナのネットワーク接続を管理するための仕様。
本ドキュメントは [CNI Spec 1.0.0](https://github.com/containernetworking/cni/blob/spec-v1.0.0/SPEC.md) を基にまとめたもの。

## 基本概念

### CNI プラグインとは

- **実行ファイル**: コンテナランタイムから呼び出される単独の実行ファイル
- **責務**: ネットワークインターフェースの作成・設定・削除
- **特徴**: ステートレス（状態管理はランタイム側の責務）

### コンテナランタイムの責務

1. コンテナ用の新しい network namespace を作成
2. コンテナ ID と network namespace パスを決定
3. Network Configuration を準備して CNI プラグインを呼び出す
4. コンテナ削除時に CNI プラグインを呼び出してクリーンアップ

## オペレーション

CNI プラグインは4つのオペレーションをサポートする。

### ADD

コンテナに新しいネットワークインターフェースを追加する。

**入力:**
- `CNI_COMMAND=ADD`
- `CNI_CONTAINERID`: コンテナの一意識別子
- `CNI_NETNS`: network namespace パス（例: `/var/run/netns/ctr-ns`）
- `CNI_IFNAME`: 作成するインターフェース名（例: `eth0`）
- `CNI_ARGS`: 追加の引数（セミコロン区切り）
- `CNI_PATH`: CNI プラグイン検索パス
- stdin: Network Configuration (JSON)

**出力:**
- 成功時: stdout に Result (JSON)
- 失敗時: stderr にエラー情報、終了コード非ゼロ

### DEL

コンテナからネットワークインターフェースを削除する。

**入力:** ADD と同じ環境変数 + stdin
**出力:**
- 成功時: 何も出力せず終了コード 0
- 失敗時: stderr にエラー情報、終了コード非ゼロ

**重要:** DEL は冪等でなければならない。既に削除済みでもエラーにしない。

### CHECK

インターフェースが正しく設定されているか確認する。

**入力:** ADD と同じ + prevResult（以前の ADD 結果）
**出力:**
- 問題なし: 終了コード 0
- 問題あり: stderr にエラー情報、終了コード非ゼロ

### VERSION

サポートする CNI バージョンを返す。

**入力:** stdin に `{"cniVersion": "1.0.0"}`
**出力:**
```json
{
  "cniVersion": "1.0.0",
  "supportedVersions": ["0.3.0", "0.3.1", "0.4.0", "1.0.0"]
}
```

## Network Configuration

プラグインへの設定は JSON 形式で stdin から渡される。

### 必須フィールド

```json
{
  "cniVersion": "1.0.0",
  "name": "my-network",
  "type": "flatnet"
}
```

| フィールド | 説明 |
|-----------|------|
| `cniVersion` | CNI 仕様のバージョン |
| `name` | ネットワーク名（ユニーク） |
| `type` | プラグイン名（実行ファイル名） |

### オプションフィールド

```json
{
  "cniVersion": "1.0.0",
  "name": "my-network",
  "type": "flatnet",
  "args": {
    "labels": { "app": "myapp" }
  },
  "ipMasq": true,
  "ipam": {
    "type": "host-local",
    "subnet": "10.10.0.0/16"
  },
  "dns": {
    "nameservers": ["8.8.8.8"],
    "domain": "example.com",
    "search": ["example.com"],
    "options": ["ndots:5"]
  }
}
```

### prevResult

CHECK および DEL 操作時に、以前の ADD の結果が `prevResult` フィールドとして渡される。

```json
{
  "cniVersion": "1.0.0",
  "name": "my-network",
  "type": "flatnet",
  "prevResult": {
    "cniVersion": "1.0.0",
    "interfaces": [...],
    "ips": [...]
  }
}
```

## Result 形式

ADD 成功時に stdout に出力する JSON。

### 完全な例

```json
{
  "cniVersion": "1.0.0",
  "interfaces": [
    {
      "name": "eth0",
      "mac": "02:42:ac:11:00:02",
      "sandbox": "/var/run/netns/ctr-ns"
    },
    {
      "name": "veth1234",
      "mac": "02:42:ac:11:00:01"
    }
  ],
  "ips": [
    {
      "address": "172.17.0.2/16",
      "gateway": "172.17.0.1",
      "interface": 0
    }
  ],
  "routes": [
    {
      "dst": "0.0.0.0/0",
      "gw": "172.17.0.1"
    }
  ],
  "dns": {
    "nameservers": ["8.8.8.8"],
    "domain": "example.com",
    "search": ["example.com"]
  }
}
```

### interfaces

| フィールド | 説明 |
|-----------|------|
| `name` | インターフェース名 |
| `mac` | MAC アドレス |
| `sandbox` | network namespace パス（コンテナ内の場合） |

### ips

| フィールド | 説明 |
|-----------|------|
| `address` | IP アドレス（CIDR 形式） |
| `gateway` | ゲートウェイ IP（オプション） |
| `interface` | interfaces 配列のインデックス |

### routes

| フィールド | 説明 |
|-----------|------|
| `dst` | 宛先ネットワーク（CIDR 形式） |
| `gw` | ゲートウェイ IP |

## エラー形式

失敗時は stderr に JSON 形式でエラーを出力し、非ゼロの終了コードで終了する。

```json
{
  "cniVersion": "1.0.0",
  "code": 7,
  "msg": "failed to create interface",
  "details": "interface eth0 already exists"
}
```

### エラーコード一覧

| コード | 説明 |
|--------|------|
| 1 | Incompatible CNI version |
| 2 | Unsupported field in network configuration |
| 3 | Container unknown or does not exist |
| 4 | Invalid necessary environment variables |
| 5 | I/O failure |
| 6 | Failed to decode content |
| 7 | Invalid network config |
| 11 | Try again later |
| 100+ | プラグイン固有のエラー |

## Network Configuration List（チェーン）

複数のプラグインを順番に実行できる。

```json
{
  "cniVersion": "1.0.0",
  "name": "my-network",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "mybridge"
    },
    {
      "type": "portmap",
      "capabilities": {"portMappings": true}
    }
  ]
}
```

- ADD: 配列順に実行、各プラグインの出力が次の入力の `prevResult` になる
- DEL: 逆順に実行

## 環境変数まとめ

| 変数 | 説明 | 例 |
|------|------|-----|
| `CNI_COMMAND` | オペレーション | `ADD`, `DEL`, `CHECK`, `VERSION` |
| `CNI_CONTAINERID` | コンテナ ID | `abc123def456` |
| `CNI_NETNS` | network namespace パス | `/var/run/netns/ctr-ns` |
| `CNI_IFNAME` | インターフェース名 | `eth0` |
| `CNI_ARGS` | 追加引数 | `IgnoreUnknown=true;K8S_POD_NAME=mypod` |
| `CNI_PATH` | プラグイン検索パス | `/opt/cni/bin` |

## Flatnet CNI への適用

Flatnet CNI プラグインは以下を実装する:

1. **ADD**: veth ペア作成、IP 割り当て（IPAM）、ブリッジ接続
2. **DEL**: インターフェース削除、IP 解放
3. **CHECK**: インターフェース存在確認
4. **VERSION**: サポートバージョン返却

### 想定する Network Configuration

```json
{
  "cniVersion": "1.0.0",
  "name": "flatnet",
  "type": "flatnet",
  "bridge": "flatnet0",
  "ipam": {
    "type": "flatnet-ipam",
    "subnet": "10.42.0.0/16",
    "gateway": "10.42.0.1"
  },
  "mtu": 1500
}
```

## 参考リンク

- [CNI Spec 1.0.0](https://github.com/containernetworking/cni/blob/spec-v1.0.0/SPEC.md)
- [CNI Plugins](https://github.com/containernetworking/plugins)
- [libcni](https://github.com/containernetworking/cni/tree/main/libcni)
