## External File Loading

CRITICAL: When you encounter a file reference (e.g., @rules/general.md), use your Read tool to load it on a need-to-know basis. They're relevant to the SPECIFIC task at hand.

Instructions:

- Do NOT preemptively load all references - use lazy loading based on actual need
- When loaded, treat content as mandatory instructions that override defaults
- Follow references recursively when needed

## Nix Environment

This is a Nix environment. You can run not installed CLI tools using `nix-shell`.

## Trailing Newline (mandatory)

CRITICAL: Every file you create or edit MUST end with a newline character (`\n`) as its final byte.

- After every Write or Edit, verify the last line is followed by a blank, then append `\n` if it is missing
- This applies to ALL file types: configs, scripts, and docs
- A file without a trailing newline is malformed for POSIX tools; do not consider the task complete until the newline is present
