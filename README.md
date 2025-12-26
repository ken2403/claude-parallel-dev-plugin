# Parallel Workspace

Git worktreeとtmuxを使用した並列開発環境のためのツールキット。

## 概要

複数のブランチで同時に作業するためのworktreeを自動作成し、tmuxセッションで管理します。
オプションでWarp terminalと連携してタブ形式で開くこともできます。

## セットアップ

### 1. 設定ファイルの編集

`config.yaml` を編集してプロジェクトに合わせた設定を行います：

```yaml
# プロジェクト名 (tmuxセッション名のプレフィックス)
project_name: "my-project"

# 新規ブランチ作成時の派生元
base_branch: "main"

# UIモード: warp または tmux
ui_mode: "warp"

# Warp URIスキーム
warp_scheme: "warp"
```

### 2. 対象リポジトリでの実行

スクリプトは対象リポジトリ内から相対パスで実行します：

```bash
cd your-project
../.paralell/spinup.sh feature/task1 feature/task2
```

## スクリプト

### spinup.sh - 並列環境の起動

```bash
../.paralell/spinup.sh <branch1> [branch2] ...
```

**動作**:
1. リポジトリの親ディレクトリに `wt-<branch名>` としてworktreeを作成
2. 各worktreeに対応するtmuxセッションを起動
3. `ui_mode: warp` の場合、Warp terminalでタブとして開く
4. `ui_mode: tmux` の場合、バックグラウンドでセッションのみ作成

### teardown.sh - 並列環境の終了

```bash
../.paralell/teardown.sh [options] <branch1> [branch2] ...

# オプション:
#   --keep-branches  ブランチを削除せずに保持
#   --dry-run        実際には実行せず、何が行われるか表示
```

### open-warp-windows.sh - Warp terminal連携

spinup.shから自動的に呼び出されます。単独で使用する場合：

```bash
../.paralell/open-warp-windows.sh <branch1> [branch2] ...
```

## 設定オプション

| 設定項目 | デフォルト値 | 説明 |
|---------|-------------|------|
| `project_name` | my-project | tmuxセッション名のプレフィックス |
| `base_branch` | main | 新規ブランチ作成時の派生元 |
| `ui_mode` | warp | `warp`: Warpでタブを開く / `tmux`: バックグラウンドのみ |
| `warp_scheme` | warp | Warp URI スキーム (warp / warppreview) |

## 使用例

### Warpでタブを開く場合

```yaml
# config.yaml
project_name: "my-app"
base_branch: "develop"
ui_mode: "warp"
```

```bash
cd my-app
../.paralell/spinup.sh feature/auth feature/api feature/ui
# → Warpで3つのタブが開く
```

### バックグラウンドで実行する場合

```yaml
# config.yaml
project_name: "my-app"
base_branch: "develop"
ui_mode: "tmux"
```

```bash
cd my-app
../.paralell/spinup.sh feature/auth feature/api

# セッション一覧
tmux list-sessions

# セッションにアタッチ
tmux attach -t my-app__feature-auth
```

## tmuxセッションの操作

```bash
# セッション一覧
tmux list-sessions

# セッションにアタッチ
tmux attach -t <session_name>

# セッションの出力を確認
tmux capture-pane -t <session_name> -p | tail -50

# セッションを終了
tmux kill-session -t <session_name>
```

## worktreeの操作

```bash
# worktree一覧
git worktree list

# worktreeを削除
git worktree remove /path/to/worktree

# 強制削除
git worktree remove --force /path/to/worktree
```

## トラブルシューティング

### worktreeが見つからない
```bash
git worktree list
```

### tmuxセッションが見つからない
```bash
tmux list-sessions
```

### 強制クリーンアップ
```bash
# worktreeを強制削除
git worktree remove --force /path/to/worktree

# tmuxセッションを強制終了
tmux kill-session -t session_name
```
