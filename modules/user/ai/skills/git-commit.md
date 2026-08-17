---
name: git-commit
description: Create conventional commits from all currently tracked files
---

Create one or more meaningful, atomic commits from the pending changes to already-tracked files.

Scope of changes:
- Stage all modifications and deletions to files that are already tracked.
- Never stage or commit untracked (new) files; leave them untracked.
- If the changes span clearly unrelated concerns, split them into separate commits, each scoped to one logical change. Otherwise, use a single commit.

Message format — follow Conventional Commits (https://www.conventionalcommits.org/en/v1.0.0/#specification):
- Format: <type>([optional scope])[!]: <description>
- Types: feat, fix, refactor, docs, test, chore, style, perf, build, ci — choose based on the actual nature of the change.
- Scope: add one when it's clearly identifiable (e.g., a module, package, or directory name). Check the last ~30 commit subjects for an existing matching scope and reuse it exactly; otherwise derive a short, lowercase scope from the primary changed path.
- Use "!" after scope or after type if there is no scope and a "BREAKING CHANGE:" footer if the change breaks backward compatibility.

Message style — follow the 50/72 rule and standard best practices:
- Subject line: imperative mood, no trailing period, ideally ≤50 characters, never exceed 72.
- Leave a blank line between subject and body.
- Body: wrap at 72 characters. Include a body when the change needs explanation of what/why (not how) — skip it for trivial, self-evident changes.

Output:
- After committing, summarize in plain language what was committed and why the messages were structured that way.
- Never reference any non committed files inside of the commit message.
