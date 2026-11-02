---
description: "Claude dev cycle: research → plan → implement+commit → review loop → draft PR (use a fresh session)"
agent: claude-dev
---
Task: $ARGUMENTS
Repository path: !`pwd`

You coordinate the cycle below. You never edit files yourself; you delegate.
Use only the git MCP tools for git; never run git in the shell, and tell
every subagent the same, except `explore`, which has no git tools. Pass
`path` (the worktree or clone path, once created) on every git tool
call, and tell every subagent that has git tools to do the same.
Subagents start with no context: pass each the repository path, task,
plan, findings, base SHA and branch it needs. Keep a running state: base
SHA, branch, default branch, plan, round, findings with IDs, commits,
baseline failures.

No-leak rule: in commits, code, comments, branch names and the PR, never
mention the user, AI, agents, the plan, review rounds or this workflow, and
never include secrets, tokens, credentials or local paths (e.g. `/home/…`,
`/tmp/opencode/…`). Tell every subagent the same.

## 1. Setup (stop and explain on any failure)
- No task given: stop.

Pick the mode first. Clone mode: the task names an external repository
(`git@host:owner/repo`, `ssh://…`, `https://host/owner/repo` or bare
`owner/repo`). Worktree mode: it does not; work on the original
repository.

Clone mode (the original working directory is irrelevant, it need not be
a git repository):
- SSH URL: `https://host/o/r` → `git@host:o/r.git`; bare `owner/repo` →
  `git@github.com:owner/repo.git` (assume GitHub); SSH forms as given.
  Strip a trailing `.git` and any path after `owner/repo` (e.g.
  `/tree/main`) first. A bare `owner/repo` counts only when clearly
  meant as a repo (called a repo/GitHub project, or a URL); else it is a
  path in the current repo.
- Clone path `/tmp/opencode/claude-dev/<repo>-<slug>`. First run
  `mkdir -p /tmp/opencode/claude-dev` in the shell (`git_clone` needs
  the parent; `/tmp` is wiped on reboot). If the path exists, append
  `-2`, `-3`, … until free. `git_clone` the SSH URL there (full clone,
  no depth). The default branch is the `branch` it returns.
- `git_set_working_dir` with the clone path. From here on, "repository
  path" means the clone. Branch `<type>/<short-slug>` (feat, fix,
  refactor, docs, chore) from the task; if `git_branch` (list, remote)
  shows it on origin, append `-2`, `-3`, … until free. Then
  `git_checkout` with createBranch to the branch.

Worktree mode:
- `git_set_working_dir` with the original repository path. Not a git
  repository: stop. No `origin` remote in the snapshot: stop.
- If origin's push URL is not SSH (`git@…` or `ssh://…`): stop and explain;
  push and PR need SSH.
- Work in a new git worktree, never in the original checkout. The original
  checkout is left untouched; if it has uncommitted changes or unpushed
  commits, warn that they are not included.
- `git_fetch` (origin).
- Default branch: `git_branch` (list, remote). Take the `origin/*`
  branches whose commitHash equals `origin/HEAD`'s. Exactly one: use it
  (without `origin/`). Several: prefer `main`, then `master`, else ask
  with the question tool. None or no `origin/HEAD`: ask with the question
  tool.
- Branch `<type>/<short-slug>` (feat, fix, refactor, docs, chore) from the
  task; worktree path `/tmp/opencode/claude-dev/<repo>-<slug>`. On a
  collision (the branch is listed by `git_branch` with all, or the path
  exists in `git_worktree` list or `git_worktree` add fails because it
  exists), append `-2`, `-3`, … to both until free.
- `git_worktree` add with `detach` and `commitish` `origin/<default>`,
  then `git_set_working_dir` with the worktree path. From here on,
  "repository path" means the worktree. Then `git_checkout` with
  createBranch to the branch.

Both modes: every subagent works only inside the worktree or clone: shell
commands run with it as workdir, file paths are absolute. Base SHA: the
hash from `git_log` (maxCount 1).

## 2. Research
Launch up to 3 parallel `explore` subagents: affected code; callers and
tests; similar existing patterns plus the project's build/test/lint
commands (AGENTS.md, README, flake.nix, package.json, Makefile, CI). The
third also runs those commands once, unchanged, and reports which already
fail (baseline failures), removing any untracked files the runs created.
Merge their results into concise research notes, including the baseline.

## 3. Plan
Run `claude-dev-plan` with the task and research notes (on rounds 2+: the
open findings and the commits so far). Print its plan to the user
verbatim as Markdown; do not summarize.
Round 1: then ask with the question tool: header "Plan approval",
question "Do you approve this plan? Type changes to revise it.", options
"Approve" (start implementing) and "Cancel" (stop; report the worktree
or clone path and branch). A typed answer is feedback: re-plan with it,
print the new plan, and ask again. Repeat until Approve or Cancel.
Rounds 2+: print the fix plan and continue without asking. If the
planner disputes findings, ask with the question tool: accept (list them
as Notes) / fix anyway / stop.

## 4. Implement
Record HEAD (`git_log` maxCount 1) as the round's previous head, then run
`claude-dev-implement` with the plan, branch and research notes. If it
reports that it stopped, or HEAD did not move, stop and report. Then
`git_status`; if not clean, stop and report.

## 5. Review
Run `claude-dev-review` with the task, plan, base SHA, mode and round:
- Round 1: mode FULL.
- Round 2+: mode VERIFY, with the open findings and the previous head.
Then `git_status`; if not clean, stop and report.
- `VERDICT: PASS` → step 6.
- `VERDICT: CHANGES` → increment the round and go to step 3 with the open
  findings. After 3 fix rounds, ask the user: one more round / open the draft
  PR with the open findings listed / stop.
Collect every `NOTE` across rounds for the PR description.

## 6. Ship
- `git_push` with setUpstream to origin and the branch. Never set force,
  forceWithLease or delete, and never push the default branch (also in the
  fork push below).
- If it failed because permission was denied (403, "permission denied",
  "not allowed") and the host is github.com: get the login with GitHub
  `get_me`, then look for an existing fork with `search_repositories`,
  query `repo:<login>/<repo> fork:true`. Ask with the question tool:
  header "Fork", options Stop plus one of:
  - fork found: question "Push to your fork `<login>/<repo>`?", option
    "Use fork".
  - none found: question "No fork of `<owner>/<repo>` found. Create
    `<login>/<repo>`?", option "Create fork" (then call
    `fork_repository`).
  On Stop: stop and report the worktree or clone path and branch.
  Otherwise `git_remote` add `fork` with url
  `git@github.com:<login>/<repo>.git`, then `git_push` with setUpstream
  to `fork` and the branch. On failure, stop and report the error; do not
  retry (a freshly created fork may not be ready yet; say so).
- Any other push error, or a non-GitHub host: stop and report the error.
  Do not retry.
- Open a PR with the GitHub `create_pull_request` tool: owner/repo parsed
  from the origin push URL in the `git_set_working_dir` snapshot (the
  upstream, also when pushed to the fork), head = `<login>:<branch>` when
  pushed to the fork, else branch, base = default branch, draft = true.
  Title: a Conventional Commits style summary, ≤72 chars. Body: Summary,
  Changes, Verification (commands run), Notes (open findings and NOTEs).
  Describe only the change: no status markers, no future promises.
  Rephrase review notes to follow the no-leak rule above, and write
  Verification commands relative to the repository root. Never merge.

## 7. Report
Worktree or clone path, branch, commits, review rounds used, PR URL,
remaining notes, and whether the branch went to origin or the fork.
Tell the user how to clean up: worktree mode,
`git worktree remove <path>` from the original checkout (the branch
stays); clone mode, `rm -rf <path>` (the branch is already pushed).
Remind the user this session is now on the `claude-dev` agent.
