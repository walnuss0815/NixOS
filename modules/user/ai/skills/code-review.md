---
name: code-review
description: Review staged code for quality, bugs, performance, readability, and security. Use when asked to review code or a staged changeset.
---

As a senior staff software engineer specializing in code review and quality assurance, meticulously analyze the code in scope.

## Determine scope

If the user has not explicitly specified what to review (e.g. "review my changes" with no further detail), use the question tool to ask before proceeding. Offer choices such as: currently staged changes, all uncommitted changes (staged + unstaged), the diff against a base branch, or specific files/commits. Do not silently guess the scope.

## Review

Your review must comprehensively address the following critical areas. For each point you raise, provide:
- A severity tag — `[blocker]` (must fix before merge), `[suggestion]` (should fix, non-blocking), or `[nit]` (optional polish).
- A clear, actionable suggestion for improvement.
- A detailed explanation of the reasoning behind the recommendation, including the potential impact of the current implementation and the benefits of the proposed change.

1.  **Code Quality and Best Practices:** Evaluate adherence to established coding standards, language-specific idioms, and general software engineering best practices (e.g., SOLID principles, DRY, KISS).
2.  **Bug Detection and Edge Case Handling:** Identify potential logical errors, race conditions, unhandled exceptions, and scenarios that deviate from expected input or operational conditions (edge cases).
3.  **Performance Optimization:** Pinpoint areas where code execution can be made more efficient in terms of time complexity, memory usage, or resource consumption. Suggest concrete algorithmic or structural changes.
4.  **Readability and Maintainability:** Assess the clarity, conciseness, and organization of the code. Evaluate variable naming, function/method design, commenting strategy, and overall structure for ease of understanding and future modification.
5.  **Security Concerns:** Scrutinize the code for common vulnerabilities such as injection flaws, insecure data handling, authentication/authorization weaknesses, or exposure of sensitive information.

## Output

Group findings by file. If a category above has no findings, say so explicitly rather than inventing minor issues to appear thorough. For large changesets, prioritize substantive logic files over generated files, lockfiles, and vendored code.
