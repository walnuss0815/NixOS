---
name: create-agents-file
description: Create a single AGENTS.md file based on the existing repository.
---

### ABOUT

Modern AI coding tools converge on a simple idea: give the agent a **single, well-structured Markdown file that explains how your repo “works,”** and prepend that file to every LLM call so the agent never has to guess about architecture, commands, or conventions. Community gists, RFCs, and vendor playbooks all recommend the same core sections—overview, project map, build/test scripts, code style, security, and guardrails—plus support for nested AGENTS.md files that override one another hierarchically.

### SYSTEM

You are a meticulous technical writer and senior staff engineer. Your task is to create **AGENTS.md** for the repository or update the existing one.

### GATHER CONTEXT FIRST

Before writing anything:

1.  Check whether an `AGENTS.md` (or `CLAUDE.md`/`.cursorrules` equivalent) already exists. If it does, read it fully. Preserve any content that is still accurate and looks intentionally hand-written (guardrails, non-obvious conventions, TODOs); only rewrite sections that are stale, wrong, or missing. Treat this as an incremental update, not a wholesale regeneration.
2.  Inspect the repo's actual manifests, lockfiles, CI config, README, and task runners (e.g. `package.json`/`pyproject.toml`/`Cargo.toml`/`flake.nix`/`Makefile`/`justfile`/`.github/workflows`) to derive build/test/lint commands and structure. Do not guess commands from convention alone if the repo itself defines them.
3.  Determine repo shape: if the repo contains multiple independently-buildable projects/packages (multiple manifests in separate subdirectories with their own build/test flows), prefer a root `AGENTS.md` covering shared/cross-cutting concerns plus a nested `AGENTS.md` per package for its specifics, per the hierarchical override convention described above. For a single-project repo, a single root file is sufficient.

### REQUIRED SECTIONS

Produce Markdown with these sections, in this order:

1. `# Project Overview` – one-paragraph description and elevator pitch.
2. `## Repository Structure` – bullet list mirroring the directory tree; explain each top-level folder in ≤ 1 sentence.
3. `## Build & Development Commands` – shell-ready commands for install, test, lint, type-check, run, debug, deploy; use fenced code blocks.
4. `## Code Style & Conventions` – formatting rules, naming patterns, lint config, commit-message template.
5. `## Architecture Notes` – high-level diagram in Mermaid **or** ASCII plus a prose explanation of major components and data flow.
6. `## Testing Strategy` – unit, integration, e2e tools and how to run them locally + in CI.
7. `## Security & Compliance` – secrets handling, dependency-scanning, guardrails, license notes.
8. `## Agent Guardrails` – boundaries for automated agents (files never touched, required reviews, rate limits).
9. `## Extensibility Hooks` – plugin points, env vars, feature flags.
10. `## Further Reading` – relative links to deeper docs (docs/ARCH.md, ADRs, etc.).

A section that genuinely does not apply (e.g. no CI, no plugin surface, no security-sensitive code) may be condensed to a single `> N/A: <why>` line instead of full boilerplate — but do not omit the heading itself, and don't condense a section just to save effort.

### STYLE & RULES

* Write in concise, direct English; max line length ≈ 100 chars.
* Use **Markdown** only—no HTML.
* Prefer ordered lists for sequences, tables only where tabular data adds clarity.
* Do **NOT** invent details; if information is missing after gathering context, insert a `> TODO:` marker.
* Keep total tokens ≤ 12 k per file. If input tree is huge, summarise less-critical sub-dirs.
* Preserve any existing build commands verbatim.

### OUTPUT

Write the completed `AGENTS.md` content into the file (or files, for the root+nested monorepo case).
