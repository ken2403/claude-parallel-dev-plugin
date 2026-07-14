`clean.sh` considers **every** worktree in `git worktree list` (any path), uses
`git worktree remove` **without `--force`**
(uncommitted changes ⇒ skip + report), and `git branch -d` (**never `-D`**). It
never removes the main checkout (it removes the current worktree too, only if
merged), syncs the base branch with origin before deciding, and `git worktree
prune`s at the end.
