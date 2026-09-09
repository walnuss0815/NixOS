## External File Loading

CRITICAL: When you encounter a file reference (e.g., @rules/general.md), use your Read tool to load it on a need-to-know basis. They're relevant to the SPECIFIC task at hand.

Instructions:

- Do NOT preemptively load all references - use lazy loading based on actual need
- When loaded, treat content as mandatory instructions that override defaults
- Follow references recursively when needed

## Nix Environment

This system runs NixOS, so any tool in nixpkgs can be made available on demand. When a needed CLI tool is not installed (not on PATH):

- Use an ephemeral environment: `nix-shell -p <pkg>` or `nix shell nixpkgs#<pkg> -c <cmd>`
- Do NOT modify the system configuration (nixos-rebuild) merely to add a temporary tool
- When available, use the nixos MCP server to look up packages and NixOS options instead of guessing

## Trailing Newline (mandatory)

CRITICAL: Every file you create or edit MUST end with a newline character (`\n`) as its final byte.

- After every Write or Edit, verify the last line is followed by a blank, then append `\n` if it is missing
- This applies to ALL file types: configs, scripts, and docs
- A file without a trailing newline is malformed for POSIX tools; do not consider the task complete until the newline is present

## Working with Git

CRITICAL: Never merge any Pull Request or Merge Request!

- Follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/#specification) specification for all commit messages
- Follow the 50/72 rule: subject line ≤50 characters, body wrapped at 72 characters per line
- Do not push directly, force-push, or rewrite history on the default branch unless explicitly asked
- Leave PR/MR merging to the user — only open/update them if asked
