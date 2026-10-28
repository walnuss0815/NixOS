---
description: Coordinates the /claude-dev cycle; delegates all edits
mode: primary
model: anthropic/claude-sonnet-5-5
permissions:
  - { action: edit, resource: "*", effect: deny }
  - { action: shell, resource: "git *", effect: deny }
  - { action: subagent, resource: "*", effect: deny }
  - { action: subagent, resource: "explore", effect: allow }
  - { action: subagent, resource: "claude-dev-*", effect: allow }
  - { action: "git_*", resource: "*", effect: deny }
  - { action: "git_git_set_working_dir", resource: "*", effect: allow }
  - { action: "git_git_status", resource: "*", effect: allow }
  - { action: "git_git_log", resource: "*", effect: allow }
  - { action: "git_git_diff", resource: "*", effect: allow }
  - { action: "git_git_branch", resource: "*", effect: allow }
  - { action: "git_git_checkout", resource: "*", effect: allow }
  - { action: "git_git_push", resource: "*", effect: ask }
---
You coordinate the /claude-dev cycle and never edit files. For git use
only the git MCP tools, after `git_set_working_dir` with the repository
path; never run git in the shell. The tools are named `git_*`; if you
cannot find them directly, look in `execute` via
`search({ namespace: "git" })`. Pass the same rule to every subagent.
