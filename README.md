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

このリポジトリを対象プロジェクトの親ディレクトリに配置します：

```
parent-directory/
├── .paralell/              # このプラグイン
├── your-project/           # 対象プロジェクト
└── other-project/          # 他のプロジェクト
```

### 2. 設定ファイルの作成

```bash
cd .paralell
cp config.example.yaml config.local.yaml
```

`config.local.yaml` を編集：

```yaml
# プロジェクト名 (tmuxセッション名のプレフィックス)
project_name: "your-project"

# 新規ブランチ作成時の派生元
base_branch: "main"

# UIモード: warp または tmux
ui_mode: "tmux"

# Warp URIスキーム (ui_mode: warp の場合)
warp_scheme: "warp"
```

### 3. Claude Codeでプラグインを有効化

```bash
cd your-project
claude --plugin-dir ../.paralell
```

または、設定ファイルに追加：

```json
// ~/.claude/settings.json
{
  "plugins": [
    "/path/to/.paralell"
  ]
}
```

### 4. プロジェクトにCLAUDE.mdを配置（推奨）

```bash
cp ../.paralell/examples/CLAUDE.project-template.md ./CLAUDE.md
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

## サブエージェント

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

- `hooks-python.json` - Python用（ruff/black自動フォーマット）
- `hooks-javascript.json` - JavaScript/TypeScript用（prettier/eslint）
- `hooks-go.json` - Go用（gofmt/goimports）

プロジェクトに適用するには：

```bash
mkdir -p .claude
cp ../.paralell/examples/hooks-python.json .claude/settings.json
```

## ディレクトリ構造

```
.paralell/
├── plugin.json              # プラグインマニフェスト
├── config.example.yaml      # 設定テンプレート
├── config.local.yaml        # ローカル設定（.gitignore）
│
├── commands/                # スラッシュコマンド
│   ├── design.md
│   ├── decompose.md
│   ├── orchestrate.md
│   ├── worker.md
│   ├── status.md
│   ├── review.md
│   ├── fix.md
│   ├── merge.md
│   ├── cleanup.md
│   └── resolve-conflicts.md
│
├── agents/                  # サブエージェント
│   ├── explorer.md          # 高速探索 (Haiku)
│   └── analyzer.md          # 詳細分析 (Sonnet)
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
├── spinup.sh               # 並列環境起動スクリプト
├── teardown.sh             # 並列環境削除スクリプト
├── open-warp-windows.sh    # Warp連携スクリプト
│
├── CLAUDE.example.md       # オーケストレーター向けガイド
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
