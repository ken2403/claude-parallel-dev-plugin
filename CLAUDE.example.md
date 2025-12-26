# Parallel Task Execution Guide

このドキュメントは、複数のClaudeエージェントを並列実行してタスクを効率的に処理するためのガイドです。

## ツールキットの場所

並列実行用スクリプトは `.paralell/` ディレクトリにあります：

- `spinup.sh` - 並列環境の起動
- `teardown.sh` - 並列環境の終了
- `config.local.yaml` - 設定ファイル

## Quick Start

**重要**: スクリプトは対象Gitリポジトリ内から相対パスで実行してください。

```bash
# 対象リポジトリに移動
cd <target-repository>

# 並列環境を起動（例: 3ワーカー）
../.paralell/spinup.sh feature/task1 feature/task2 feature/task3

# 環境を終了
../.paralell/teardown.sh feature/task1 feature/task2 feature/task3
```

---

## オーケストレーターとしての責務

大規模タスクを受け取った場合、以下のフローで並列処理を検討してください。

### 1. タスク分析

並列化の判断基準：

- [ ] タスクが独立したサブタスクに分割可能か
- [ ] 各サブタスクが異なるファイル/ディレクトリを対象とするか
- [ ] 並列化による時間短縮効果があるか

**並列化すべきケース**:
- 複数の独立した機能実装
- 異なるモジュールへの変更
- テスト追加とリファクタリングの同時進行

**並列化すべきでないケース**:
- 共有ファイルへの同時変更が必要
- 順序依存のある変更
- 小規模で単一ファイルの修正

### 2. ワーカー起動

```bash
cd <target-repository>
../.paralell/spinup.sh <branch1> <branch2> <branch3>
```

### 3. タスク投入

`tmux send-keys` で `claude -p` コマンドを送信：

```bash
tmux send-keys -t '<project>__<branch>' \
  'claude -p "<タスク指示>"' Enter
```

### 4. 進捗監視

```bash
# セッション一覧
tmux list-sessions

# 特定セッションの出力確認
tmux capture-pane -t '<session>' -p | tail -50
```

### 5. 統合・マージ

各ブランチの作業完了後、mainブランチにマージ。

### 6. クリーンアップ

```bash
../.paralell/teardown.sh <branch1> <branch2> <branch3>
```

---

## ガードレール

### MUST（必須）

1. **スコープの明確化**: 各ワーカーに担当ファイル/ディレクトリを明示する
2. **境界の設定**: 他ワーカーが触れてはいけないファイルを指定する
3. **完了条件の明示**: 何をもって完了とするか具体的に伝える
4. **base branchの指定**: PR作成時のbase branchを明示する

### MUST NOT（禁止）

1. **共有ファイルの同時編集禁止**: 複数ワーカーが同じファイルを編集しない
2. **依存関係の無視禁止**: 順序依存がある場合は並列化しない
3. **監視なしの放置禁止**: 定期的に進捗を確認する
4. **コンフリクト放置禁止**: 発生したら即座に対処する

### SHOULD（推奨）

1. タスクサイズを均等に分割する
2. 各ワーカーにコミットメッセージのプレフィックスを指定する
3. 問題発生時は早めに介入する
4. マージ前に各ブランチの変更内容を確認する

---

## タスク分割パターン

### パターンA: 機能別分割

```
Worker 1: 認証機能 (src/auth/)
Worker 2: ダッシュボード (src/dashboard/)
Worker 3: API層 (src/api/)
```

### パターンB: レイヤー別分割

```
Worker 1: フロントエンド (components/, pages/)
Worker 2: バックエンド (server/, api/)
Worker 3: テスト (tests/)
```

### パターンC: タスク種別分割

```
Worker 1: 新規実装
Worker 2: リファクタリング
Worker 3: テスト追加
```

---

## ワーカーへの指示テンプレート

```
あなたは「<タスク名>」を担当します。

## 担当範囲
- 対象: `<directory>/`
- 変更禁止: `<shared-directory>/`

## 実装内容
1. <具体的なタスク1>
2. <具体的なタスク2>

## 完了条件
- 実装完了
- テストパス
- lint/type checkパス

## 完了時のアクション
git commitしてPRを作成してください。base branchは `<base-branch>` にしてください。
```

---

## コンフリクト発生時の対処

```bash
# コンフリクト解消指示を送信
tmux send-keys -t '<session>' \
  'claude -p "mainブランチをマージしてコンフリクトを解消し、再度pushしてください。"' Enter
```

---

## トラブルシューティング

### セッションが見つからない

```bash
tmux list-sessions
```

### worktreeの状態確認

```bash
git worktree list
```

### 強制クリーンアップ

```bash
git worktree remove --force /path/to/worktree
tmux kill-session -t <session>
```

---

## 設定ファイル

`.paralell/config.local.yaml` で以下を設定：

| 項目 | 説明 |
|------|------|
| `project_name` | tmuxセッション名のプレフィックス |
| `base_branch` | 新規ブランチの派生元 |
| `ui_mode` | `warp`（タブ表示）または `tmux`（バックグラウンド） |
| `warp_scheme` | Warp URI スキーム |
