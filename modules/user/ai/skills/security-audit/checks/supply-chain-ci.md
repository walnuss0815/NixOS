# Check: supply chain, CI and logging

OWASP: CICD-SEC-3 Dependency Chain Abuse, CICD-SEC-7 Insecure System Configuration, CICD-SEC-8 Ungoverned Usage of 3rd Party Services, CICD-SEC-9 Improper Artifact Integrity Validation, CICD-SEC-10 Insufficient Logging and Visibility, K10 Inadequate Logging And Monitoring.

## Pinning and provenance (CICD-SEC-3, -9)

- From the inventory: which components are pinned by digest or commit SHA, which only by tag or branch. Mutable refs on code that handles secrets or runs with cluster rights (Terraform modules with `?ref=<tag>`, images by tag, Helm charts by version from mutable repos, GitHub Actions by tag) are findings.
- Vendored trees: is there a lock with upstream SHAs (vendir, git subtree notes)? Can the vendored copy drift from the lock unnoticed (a check in CI)?
- Signature or provenance verification anywhere (cosign, Kyverno `verifyImages`, Flux `verify`, Nix hashes)? Absence is Low unless tenants or third parties push images the platform runs.

## CI (CICD-SEC-4, -7)

- For GitHub Actions run:

  ```bash
  "$(bash <skill-dir>/scripts/tool.sh zizmor)" --offline --format plain <repo>/.github/workflows
  ```

  If `tool.sh` exits 1, list zizmor under "Not checked" and do the manual checks. Report each zizmor finding with its rule and `path:line`. Check by hand as well: `permissions:` (default token scope), `pull_request_target` and `workflow_run` with checkout of untrusted refs, secrets available to PR jobs, self-hosted runners on public repos.
- GitLab CI: protected variables and branches, `rules` for forks/MRs, runner tags.
- Does CI hold cloud or cluster credentials? Which jobs?

## Third-party services (CICD-SEC-8)

- Committed configs for bots and apps: Renovate/Dependabot (automerge on which packages?), and whether vulnerability alerts are disabled (repo setup scripts that turn them off).
- External services in the data path that the repo's stated goals exclude (e.g. a design that forbids non-EU processors).

## Logging and visibility (K10, CICD-SEC-10)

- API server audit policy configured? Where do audit logs go, and how long are they kept?
- GitOps tool and IdP event logs (login failures, admin events) collected?
- Alerting on security-relevant signals (failed auth bursts, policy denials, new ClusterRoleBindings)?

Deep reference: https://cheatsheetseries.owasp.org/cheatsheets/GitHub_Actions_Security_Cheat_Sheet.html
