---
description: "Claude dev cycle: research → plan → implement+commit → review loop → draft PR (use a fresh session)"
agent: claude-dev
---
Task: $ARGUMENTS
Repository path: !`pwd`

You coordinate the cycle below. You never edit files yourself; you delegate.
Use only the git MCP tools for git; never run git in the shell, and tell
every subagent the same. Pass `path` (the clone path, once cloned) on
every git tool call, and tell every subagent, `explore` included, to do
the same. Subagents start with no context: pass each the repository
path, task, plan, findings, base SHA and branch it needs. Keep a running
state: base SHA, branch, default branch, plan, round, findings with
IDs, commits.

No-leak rule: in commits, code, comments, branch names and the PR, never
mention the user, AI, agents, the plan, review rounds or this workflow, and
never include secrets, tokens, credentials or local paths (e.g. `/home/…`,
`/tmp/opencode/…`). Tell every subagent the same.

## 1. Setup (stop and explain on any failure)
- No task given: stop.
- `git_set_working_dir` with the original repository path. Not a git
  repository: stop. No `origin` remote in the snapshot: stop.
- If origin's push URL is not SSH (`git@…` or `ssh://…`): stop and explain;
  cloning, push and PR need SSH.
- Work in a fresh clone, never in the original checkout. `git_status` on
  the original only to pick the branch: if the current branch has an
  upstream and is not ahead of it, clone that branch; otherwise clone the
  default branch and warn that unpushed commits and uncommitted changes
  are not included. A dirty tree is fine.
- `git_clone` from origin's URL to `/tmp/opencode/claude-dev/<repo>-<slug>`.
  The path exists: stop and ask. Then `git_set_working_dir` with the
  clone. From here on, "repository path" means the clone. Every subagent
  works only inside it: shell commands run with it as workdir, file paths
  are absolute.
- Default branch: `git_branch` (list, remote). Take the `origin/*`
  branches whose commitHash equals `origin/HEAD`'s. Exactly one: use it
  (without `origin/`). Several: prefer `main`, then `master`, else ask
  with the question tool. None or no `origin/HEAD`: ask with the question
  tool.
- If on the default branch: `git_checkout` with createBranch to
  `<type>/<short-slug>` (feat, fix, refactor, docs, chore) from the task.
  Otherwise stay on the current branch.
- Base SHA: the hash from `git_log` (maxCount 1).

## 2. Research
Launch up to 3 parallel `explore` subagents (read-only git MCP tools
`git_log`/`git_blame`/`git_show` for history): affected code; callers and
tests; similar existing patterns plus the project's build/test/lint
commands (AGENTS.md, README, flake.nix, package.json, Makefile, CI).
Merge their results into concise research notes.

## 3. Plan
Run `claude-dev-plan` with the task and research notes (on rounds 2+: the
open findings and the commits so far). Show the plan to the user.
First plan only: ask for approval with the question tool (approve /
change: <feedback> / cancel). On change, re-plan with the feedback.
Fix plans on later rounds proceed without approval.

## 4. Implement
Record HEAD (`git_log` maxCount 1) as the round's previous head, then run
`claude-dev-implement` with the plan, branch and research notes. Then
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
  forceWithLease or delete, and never push the default branch. On failure,
  stop and report the error. Do not retry.
- Open a PR with the GitHub `create_pull_request` tool: owner/repo parsed
  from the origin push URL in the `git_set_working_dir` snapshot, head = branch, base = default branch, draft = true.
  Title: a Conventional Commits style summary, ≤72 chars. Body: Summary,
  Changes, Verification (commands run), Notes (open findings and NOTEs).
  Describe only the change: no status markers, no future promises.
  Rephrase review notes to follow the no-leak rule above, and write
  Verification commands relative to the repository root. Never merge.

## 7. Report
Clone path, branch, commits, review rounds used, PR URL, remaining notes. Remind the
user this session is now on the `claude-dev` agent.
