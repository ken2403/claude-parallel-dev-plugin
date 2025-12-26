# 並列タスク実行オーケストレーション ガイド

このドキュメントは、複数のClaudeエージェントを並列実行してタスクを効率的に処理するためのオーケストレータAgent向けガイドです。

## アーキテクチャ概要

```
┌─────────────────────────────────────────────────────────────┐
│                    Orchestrator Agent                        │
│                  (タスク分割・割当・統合)                      │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│   Worker 1    │     │   Worker 2    │     │   Worker 3    │
│ (worktree-1)  │     │ (worktree-2)  │     │ (worktree-3)  │
│  tmux session │     │  tmux session │     │  tmux session │
│  + Claude CLI │     │  + Claude CLI │     │  + Claude CLI │
└───────────────┘     └───────────────┘     └───────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              ▼
                    ┌─────────────────┐
                    │   Main Repo     │
                    │ (統合・マージ)   │
                    └─────────────────┘
```

## スクリプト実行の前提条件

**重要**: すべてのスクリプトは、タスクを実装する対象のGitリポジトリ内部で、相対パスを指定して実行してください。

```bash
# 例: ai-agentsリポジトリで並列タスクを実行する場合
cd ai-agents
../.paralell/spinup.sh feature/task1 feature/task2
```

スクリプトは実行時のカレントディレクトリを基準にworktreeを作成するため、必ず対象リポジトリ内で実行する必要があります。

## スクリプト構成

### 1. spinup.sh - 並列環境の起動

**場所**: `.paralell/spinup.sh`

**機能**:
- 指定されたブランチ名ごとにgit worktreeを作成
- 各worktreeに対応するtmuxセッションを起動
- Warp terminalでタブとして開く

**使用方法**:
```bash
# 対象リポジトリ内で実行
cd ai-agents
../.paralell/spinup.sh <branch1> [branch2] [branch3] ...

# 例: 3つの並列ワーカーを起動
../.paralell/spinup.sh feature/auth feature/dashboard feature/api
```

**動作詳細**:
1. リポジトリの親ディレクトリに `wt-<branch名>` としてworktreeを作成
2. ブランチが存在しなければ `BASE_BRANCH` (デフォルト: main) から新規作成
3. tmuxセッション名: `${PROJECT_NAME}__${branch名}`
4. 単一ペインのtmuxセッションを作成（Warp経由でアタッチ）

### 2. teardown.sh - 並列環境の終了

**場所**: `.paralell/teardown.sh`

**機能**:
- tmuxセッションを終了
- git worktreeを削除
- オプションでブランチも削除

**使用方法**:
```bash
# 対象リポジトリ内で実行
cd ai-agents
../.paralell/teardown.sh [options] <branch1> [branch2] ...

# オプション:
#   --keep-branches  ブランチを削除せずに保持
#   --dry-run        実際には実行せず、何が行われるか表示
```

### 3. open-warp-windows.sh - Warp terminal連携

**場所**: `.paralell/open-warp-windows.sh`

**機能**:
- Warp Launch Configurationを生成
- 各worktreeを別タブで開く
- tmuxセッションに自動接続

## オーケストレーション戦略

### タスク分割の原則

1. **独立性**: 各ワーカーのタスクは互いに依存しないこと
2. **明確な境界**: ファイル/モジュール単位で分割し、コンフリクトを回避
3. **均等な負荷**: タスクサイズをなるべく均等に

### 分割パターン

#### パターンA: 機能別分割
```
Worker 1: 認証機能 (auth/)
Worker 2: ダッシュボード (dashboard/)
Worker 3: API層 (api/)
```

#### パターンB: レイヤー別分割
```
Worker 1: フロントエンド (components/, pages/)
Worker 2: バックエンド (server/, api/)
Worker 3: インフラ/テスト (infra/, tests/)
```

#### パターンC: タスク種別分割
```
Worker 1: 新規実装
Worker 2: リファクタリング
Worker 3: テスト追加
```

## オーケストレータの責務

### 1. 起動フェーズ
```bash
# 対象リポジトリに移動
cd ai-agents

# 1. タスクを分析し、必要なワーカー数を決定
# 2. ブランチ名を決定（タスク内容を反映）
# 3. spinup.shで環境を起動
../.paralell/spinup.sh task/auth task/dashboard task/api
```

### 2. タスク投入フェーズ（claude -p）

orchestratorは `tmux send-keys` で `claude -p` コマンドを送信してタスクを投入する。

**セッション一覧の確認**:
```bash
tmux list-sessions
```

**タスクの投入**:
```bash
# claude -p でプロンプトを直接渡す
tmux send-keys -t 'ai-agents__feature-auth' \
  'claude -p "認証機能を実装してください。.claude/tasks/auth.mdを読んで実装し、完了したらgit commitしてPRを作成してください。base branchは main にしてください。"' Enter

tmux send-keys -t 'ai-agents__feature-dashboard' \
  'claude -p "ダッシュボード機能を実装してください。.claude/tasks/dashboard.mdを読んで実装し、完了したらgit commitしてPRを作成してください。base branchは main にしてください。"' Enter
```

**タスク指示のベストプラクティス**:
- 担当範囲（ファイル/ディレクトリ）を明確に指定
- 具体的な実装内容を記載
- 完了条件を明示
- 他ワーカーとの境界（触れてはいけないファイル）を指定

### 3. 進捗監視フェーズ

**各セッションの出力を確認**:
```bash
for session in $(tmux list-sessions -F '#{session_name}' | grep '^ai-agents__'); do
  echo "=== $session ==="
  tmux capture-pane -t "$session" -p | tail -30
  echo ""
done
```

**特定セッションの詳細確認**:
```bash
tmux capture-pane -t 'ai-agents__feature-auth' -p | tail -50
```

**監視のポイント**:
- 各ワーカーの進捗を確認
- 問題が発生した場合は介入
- 必要に応じてタスクの再割当

### 4. PR確認・コンフリクト解消フェーズ

**Open状態のPRを確認**:
```bash
gh pr list --state open --json number,title,headRefName | jq -r '.[] | "\(.number): \(.headRefName) - \(.title)"'
```

**マージ可能か確認**:
```bash
gh pr view <PR番号> --json mergeable,mergeStateStatus
```

**コンフリクトが発生した場合の修正指示**:
```bash
tmux send-keys -t 'ai-agents__feature-dashboard' \
  'claude -p "PR #<PR番号>にコンフリクトが発生しています。mainブランチをマージしてコンフリクトを解消し、再度pushしてください。"' Enter
```

### 5. 統合フェーズ

```bash
# 各ブランチの作業が完了したら:
# 1. mainブランチにマージ
git checkout main
git merge task/auth
git merge task/dashboard
git merge task/api

# 2. コンフリクト解決（必要な場合）
# 3. 統合テスト実行
```

### 6. クリーンアップフェーズ

すべてのPRがマージ済みになったら、teardown.shでクリーンアップ:

```bash
# worktree、tmuxセッション、ローカルブランチを削除
../.paralell/teardown.sh task/auth task/dashboard task/api

# ブランチを保持したい場合
../.paralell/teardown.sh --keep-branches task/auth task/dashboard task/api
```

## ワーカーへの指示テンプレート

```markdown
## タスク: [タスク名]

### 担当範囲
- 対象ディレクトリ: `src/features/xxx/`
- 対象ファイル: `*.ts`, `*.tsx`

### 実装内容
1. [具体的なタスク1]
2. [具体的なタスク2]
3. [具体的なタスク3]

### 完了条件
- [ ] すべての実装が完了
- [ ] テストがパス
- [ ] lint/type checkがパス

### 注意事項
- `src/shared/` は変更禁止（他ワーカーと競合の可能性）
- コミットメッセージは `[xxx]` プレフィックスを使用
```

## トラブルシューティング

### tmuxセッションが見つからない
```bash
tmux list-sessions
```

### worktreeの状態確認
```bash
git worktree list
```

### 強制クリーンアップ
```bash
# worktreeを強制削除
git worktree remove --force /path/to/worktree

# tmuxセッションを強制終了
tmux kill-session -t session_name
```

## 設定可能な環境変数

| 変数名 | デフォルト値 | 説明 |
|--------|-------------|------|
| `PROJECT_NAME` | ai-agents | tmuxセッション名のプレフィックス |
| `BASE_BRANCH` | main | 新規ブランチ作成時の派生元 |
| `WARP_SCHEME` | warp | Warp terminal URIスキーム |
