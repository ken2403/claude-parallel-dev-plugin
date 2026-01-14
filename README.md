# Parallel Workflow Plugin

Git worktreeとtmuxを使用した並列開発環境のためのClaude Codeプラグイン。

## 概要

大規模な開発タスクを複数の独立したサブタスクに分解し、並列で実行することで開発効率を最大化します。

### 主な機能

- **Issue駆動の設計**: GitHub Issueから実装設計を自動生成
- **タスク分解**: 大規模タスクを並列実行可能なサブタスクに分割
- **並列ワーカー管理**: Git worktreeとtmuxで独立した作業環境を提供
- **統合レビュー**: PRレビュー、マージ、クリーンアップまでをサポート
- **高速探索**: Haikuモデルのサブエージェントによる高速コード探索

## インストール

### 1. プラグインの配置

GitHubからクローンします。プラグインは**任意のディレクトリ**に配置可能です：

```bash
# 任意のディレクトリにクローン
cd /path/to/any-directory
git clone https://github.com/ken2403/.claude-paralell-dev-plugin.git
```

配置例：

```
/opt/claude-plugins/
└── .claude-paralell-dev-plugin/  # このプラグイン
```

### 2. Claude Codeでプラグインを有効化

#### 方法A: Marketplaceとして登録（推奨）

プラグインをMarketplaceとして登録すると、どのプロジェクトでも利用可能になります：

```bash
# プラグインをMarketplaceとして追加
claude plugin marketplace add /path/to/any-directory/.claude-paralell-dev-plugin

# プラグインをインストール
claude plugin install pw@claude-parallel-dev-plugin
```

#### 方法B: 起動時にオプション指定

特定のセッションでのみ使用する場合は、`--plugin-dir`オプションを指定してClaude Codeを起動：

```bash
cd your-project
claude --plugin-dir /path/to/any-directory/.claude-paralell-dev-plugin
```

### 3. プロジェクトにCLAUDE.mdを配置（推奨）

```bash
cp ../.claude-paralell-dev-plugin/examples/CLAUDE.project-template.md ./CLAUDE.md
# プロジェクトに合わせて編集
```

## 使い方

### 基本ワークフロー

```
仕様受領 → 設計 → タスク分解 → 並列実行 → レビュー → マージ → クリーンアップ
```

### コマンド一覧

| コマンド | 説明 | 引数 |
|----------|------|------|
| `/pw:design` | 仕様から設計を作成 | `#issue番号` / `@ファイル参照` / `"テキスト"` |
| `/pw:decompose` | タスクを分解 | 設計出力またはタスク説明 |
| `/pw:orchestrate` | 並列ワーカーを起動 | ブランチ名のリスト |
| `/pw:worker` | ワーカータスクを実行 | タスク説明 |
| `/pw:status` | 進捗を確認 | (オプション) セッション名 |
| `/pw:precheck` | PR作成前の事前チェック | ブランチ名または`HEAD` |
| `/pw:review` | PRをレビュー | PR番号またはブランチ名 |
| `/pw:fix` | レビュー指摘を修正 | フィードバック内容 |
| `/pw:merge` | PRをマージ | PR番号 `[--auto]` |
| `/pw:cleanup` | 環境をクリーンアップ | ブランチ名のリスト |
| `/pw:resolve-conflicts` | コンフリクトを解消 | ブランチ名 |

### 使用例

#### 1. GitHub Issueから実装

```bash
# 設計
/pw:design #123

# タスク分解
/pw:decompose

# 並列ワーカー起動
/pw:orchestrate feature/auth feature/api feature/tests

# 進捗確認
/pw:status

# PRレビュー
/pw:review 45

# マージ
/pw:merge 45

# クリーンアップ（全PRマージ後）
/pw:cleanup feature/auth feature/api feature/tests
```

#### 2. 対話的なタスク実行

```bash
# 仕様を直接指定
/pw:design "Add OAuth2 authentication with Google and GitHub providers"

# Claudeが詳細を質問してくる場合もあります
```

#### 3. 単発タスク（並列化なし）

```bash
# 小規模なタスクはworkerコマンドを直接使用
/pw:worker Fix the null pointer exception in src/auth/login.ts
```

## 依存関係

### コンポーネント依存図

```
                                    ┌─────────────────┐
                                    │   /pw:design    │
                                    │  (設計フェーズ)  │
                                    └────────┬────────┘
                                             │ uses
                                             ▼
                              ┌──────────────────────────────┐
                              │         explorer             │
                              │      (コード探索)             │
                              └──────────────────────────────┘
                                             │
                                             ▼
                                    ┌─────────────────┐
                                    │  /pw:decompose  │
                                    │ (タスク分解)    │
                                    └────────┬────────┘
                                             │
                                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          /pw:orchestrate                                 │
│                         (ワーカー起動・管理)                               │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  calls spinup.sh → creates worktrees + tmux sessions            │    │
│  │  spawns status-monitor subagent (background)                    │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ spawns
          ┌────────────────────┼────────────────────┐
          ▼                    ▼                    ▼
   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
   │ /pw:worker  │      │ /pw:worker  │      │ /pw:worker  │
   │ (Worker 1)  │      │ (Worker 2)  │      │ (Worker N)  │
   └──────┬──────┘      └──────┬──────┘      └──────┬──────┘
          │ uses               │ uses               │ uses
          ▼                    ▼                    ▼
   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
   │  explorer   │      │  explorer   │      │  explorer   │
   │  analyzer   │      │  analyzer   │      │  analyzer   │
   └──────┬──────┘      └──────┬──────┘      └──────┬──────┘
          │ applies            │ applies            │ applies
          ▼                    ▼                    ▼
   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
   │code-quality │      │code-quality │      │code-quality │
   │security-rev │      │security-rev │      │security-rev │
   └──────┬──────┘      └──────┬──────┘      └──────┬──────┘
          │ creates PR         │ creates PR         │ creates PR
          └────────────────────┼────────────────────┘
                               ▼
                      ┌─────────────────┐
                      │   /pw:status    │◄──── status-monitor (bg)
                      │  (進捗確認)      │
                      └────────┬────────┘
                               │
                               ▼
                      ┌─────────────────┐
                      │   /pw:review    │
                      │  (PRレビュー)    │
                      └────────┬────────┘
                               │ uses
                               ▼
                      ┌─────────────────┐
                      │   code-quality  │
                      │  security-review│
                      └────────┬────────┘
                               │
          ┌────────────────────┼────────────────────┐
          ▼                    │                    ▼
   ┌─────────────┐             │             ┌─────────────┐
   │  /pw:fix    │◄────────────┘             │ /pw:resolve │
   │(指摘修正)   │                           │ -conflicts  │
   └─────────────┘                           └─────────────┘
                               │
                               ▼
                      ┌─────────────────┐
                      │   /pw:merge     │
                      │  (PRマージ)     │
                      │ ⚠️ CI+承認必須  │
                      └────────┬────────┘
                               │
                               ▼
                      ┌─────────────────┐
                      │  /pw:cleanup    │
                      │(環境クリーンアップ)│
                      │ calls teardown.sh│
                      │ ⚠️ 人間確認必須  │
                      └─────────────────┘
```

### コマンド → サブエージェント依存

| コマンド | 必須サブエージェント | オプション |
|----------|---------------------|------------|
| `/pw:design` | `explorer` | `analyzer` |
| `/pw:decompose` | `explorer` | - |
| `/pw:orchestrate` | - | `status-monitor` (バックグラウンド) |
| `/pw:worker` | `explorer` | `analyzer` |
| `/pw:status` | - | - |
| `/pw:precheck` | `explorer` | `analyzer` |
| `/pw:review` | - | `explorer`, `analyzer` |
| `/pw:fix` | `explorer` | - |
| `/pw:merge` | - | - |
| `/pw:cleanup` | - | - |
| `/pw:resolve-conflicts` | - | - |

### コマンド → スキル依存

| コマンド | 適用スキル |
|----------|------------|
| `/pw:worker` | `code-quality`, `security-review` |
| `/pw:precheck` | `code-quality`, `security-review` |
| `/pw:review` | `code-quality`, `security-review` |
| `/pw:fix` | `code-quality` |

### コマンド → スクリプト依存

| コマンド | 使用スクリプト | 機能 |
|----------|----------------|------|
| `/pw:orchestrate` | `spinup.sh` | worktree作成、tmuxセッション起動 |
| `/pw:cleanup` | `teardown.sh` | worktree削除、tmuxセッション終了 |

### サブエージェント一覧

| サブエージェント | モデル | 用途 | ツール |
|------------------|--------|------|--------|
| `explorer` | Haiku | 高速なファイル/パターン検索 | Read, Grep, Glob |
| `analyzer` | Sonnet | 詳細なアーキテクチャ分析 | Read, Grep, Glob, Bash |
| `status-monitor` | Haiku | バックグラウンド進捗監視 (30秒間隔) | Bash |

### スキル一覧

| スキル | 自動適用タイミング | 内容 |
|--------|-------------------|------|
| `code-quality` | コードレビュー時、実装時 | 可読性、保守性、型安全性、コーディングスタイル一貫性 |
| `security-review` | セキュリティ関連変更時 | OWASP Top 10、認証/認可、入力検証 |

## サブエージェント詳細

### explorer (Haiku)

高速なコード探索用。ファイル検索やパターン探索に使用。

```
Use explorer subagent to find authentication-related files
```

### analyzer (Sonnet)

詳細なコード分析用。アーキテクチャ理解や複雑な依存関係の分析に使用。

```
Use analyzer subagent to understand the payment system architecture
```

### status-monitor (Haiku)

バックグラウンド監視用。オーケストレーターが起動後、自動で進捗を監視。

- **監視間隔**: 30秒
- **最大監視時間**: 30分
- **検出**: PR作成、エラー、完了

## スキル

### code-quality

コードレビュー時に自動適用される品質基準。

### security-review

セキュリティ関連のコード変更時に自動適用されるチェックリスト。

## Hooks

### 汎用Hooks（プラグイン内蔵）

- **ファイル保護**: `.env`, `credentials`等の編集をブロック
- **通知**: 作業完了時にデスクトップ通知
- **ログ**: セッション完了をログ記録

### 言語別Hooks（プロジェクトに設定）

`examples/` ディレクトリに言語別のHooks設定例があります：

- `hooks-python.json` - Python用（ruff lint/format + mypy型チェック）
- `hooks-javascript.json` - JavaScript/TypeScript用（prettier/eslint）
- `hooks-go.json` - Go用（gofmt/goimports）

プロジェクトに適用するには：

```bash
mkdir -p .claude
cp ../.claude-paralell-dev-plugin/examples/hooks-python.json .claude/settings.json
```

## 自動検出

スクリプトは以下を自動的に検出します（設定ファイル不要）：

| 項目 | 検出方法 |
|------|----------|
| **Gitリポジトリ** | 現在のディレクトリ → サブディレクトリから自動検出 |
| **プロジェクト名** | Gitリポジトリのディレクトリ名 |
| **ベースブランチ** | `main` → `master` → 現在のブランチ（優先順） |

セッション名は `{プロジェクト名}__{ブランチ名}` 形式で自動生成されます。

### 親ディレクトリからの実行

Gitリポジトリの**親ディレクトリ**からClaudeセッションを起動して、`/pw:orchestrate` と `/pw:cleanup` を実行できます：

```
/workspace/              ← Claudeセッションを起動
├── my-project/          ← Gitリポジトリ（自動検出）
├── wt-feature-auth/     ← worktree 1（自動作成）
├── wt-feature-api/      ← worktree 2（自動作成）
└── wt-feature-tests/    ← worktree 3（自動作成）
```

この構成により：
- worktreeがリポジトリと同じ階層に作成される
- Claudeセッションから全worktreeを簡単に参照可能
- 複数リポジトリがある場合は `GIT_REPO` 環境変数で指定可能

```bash
# 複数リポジトリがある場合の指定方法
GIT_REPO=/workspace/my-project ./scripts/spinup.sh feature/auth
```

**注意**: `review`, `merge`, `fix`, `resolve-conflicts` などのコマンドはworktree内またはgitリポジトリ内から実行する必要があります。

## ディレクトリ構造

```
.claude-paralell-dev-plugin/
├── plugin.json              # プラグインマニフェスト
│
├── commands/                # スラッシュコマンド
│   ├── design.md
│   ├── decompose.md
│   ├── orchestrate.md
│   ├── worker.md
│   ├── status.md
│   ├── precheck.md
│   ├── review.md
│   ├── fix.md
│   ├── merge.md
│   ├── cleanup.md
│   └── resolve-conflicts.md
│
├── agents/                  # サブエージェント
│   ├── explorer.md          # 高速探索 (Haiku)
│   ├── analyzer.md          # 詳細分析 (Sonnet)
│   └── status-monitor.md    # バックグラウンド監視 (Haiku)
│
├── skills/                  # 自動適用スキル
│   ├── code-quality/
│   │   └── SKILL.md
│   └── security-review/
│       └── SKILL.md
│
├── hooks/                   # 汎用Hooks
│   └── hooks.json
│
├── examples/                # 設定例
│   ├── CLAUDE.project-template.md
│   ├── hooks-python.json
│   ├── hooks-javascript.json
│   └── hooks-go.json
│
├── scripts/                 # 実行スクリプト
│   ├── spinup.sh            # 並列環境起動
│   └── teardown.sh          # 並列環境削除
│
└── README.md               # このファイル
```

## ベストプラクティス

### タスク分解

- **独立性**: 各サブタスクは同じファイルを編集しない
- **完結性**: 各サブタスクは単独でマージ可能なPRを生成
- **適切な粒度**: 2-5個のサブタスクが最適

### 並列実行

- プロンプトは**常に英語**で記述（日本語出力でも）
- 定期的に`/pw:status`で進捗を確認
- ブロッカーがあれば早期に介入

### クリーンアップ

- **全PRがマージされるまでクリーンアップしない**
- `gh pr list --state open`で確認してから実行

## トラブルシューティング

### セッションが見つからない

```bash
tmux list-sessions
```

### Worktreeが見つからない

```bash
git worktree list
```

### 強制クリーンアップ

```bash
# Worktreeを強制削除
git worktree remove --force /path/to/worktree

# tmuxセッションを強制終了
tmux kill-session -t session-name

# 孤立したworktreeエントリを削除
git worktree prune
```

## 関連ドキュメント

- [Claude Code公式ドキュメント](https://docs.anthropic.com/claude-code)
- [Plugins](https://code.claude.com/docs/en/plugins)
- [Commands](https://code.claude.com/docs/en/slash-commands)
- [Subagents](https://code.claude.com/docs/en/sub-agents)
- [Skills](https://code.claude.com/docs/en/skills)
- [Hooks](https://code.claude.com/docs/en/hooks-guide)
