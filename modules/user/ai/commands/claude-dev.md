---
description: "Claude dev cycle: research → plan → implement+commit → review loop → draft PR (use a fresh session)"
agent: claude-dev
---
Task: $ARGUMENTS
Repository path: !`pwd`

You coordinate the cycle below. You never edit files yourself; you delegate.
Use only the git MCP tools for git; never run git in the shell, and tell
every subagent the same. Subagents start with no context: pass each the
repository path, task, plan, findings, base SHA and branch it needs. Keep a
running state: base SHA, branch, default branch, plan, round, findings with
IDs, commits.

## 1. Setup (stop and explain on any failure)
- No task given: stop.
- `git_set_working_dir` with the repository path. Not a git repository:
  stop. No `origin` remote in the snapshot: stop.
- Working tree not clean: stop and ask the user to commit or stash first.
- Default branch: `git_branch` (list, remote). Take the `origin/*`
  branches whose commitHash equals `origin/HEAD`'s. Exactly one: use it
  (without `origin/`). Several: prefer `main`, then `master`, else ask
  with the question tool. None or no `origin/HEAD`: ask with the question
  tool.
- If on the default branch: `git_checkout` with createBranch to
  `<type>/<short-slug>` (feat, fix, refactor, docs, chore) from the task.
  Otherwise stay on the current branch.
- Base SHA: the hash from `git_log` (maxCount 1).
- If origin's push URL is not SSH (`git@…` or `ssh://…`), ask with the
  question tool whether to continue without push/PR.

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

## 6. Ship (skip if the user chose no push in Setup)
- `git_push` with setUpstream to origin and the branch. Never set force,
  forceWithLease or delete, and never push the default branch. On failure,
  stop and report the error. Do not retry.
- Open a PR with the GitHub `create_pull_request` tool: owner/repo parsed
  from the origin push URL in the `git_set_working_dir` snapshot, head = branch, base = default branch, draft = true.
  Title: a Conventional Commits style summary, ≤72 chars. Body: Summary,
  Changes, Verification (commands run), Notes (open findings and NOTEs).
  Describe only the change: no status markers, no future promises, no
  mention of AI or of this workflow. Never merge.

## 7. Report
Branch, commits, review rounds used, PR URL, remaining notes. Remind the
user this session is now on the `claude-dev` agent.
