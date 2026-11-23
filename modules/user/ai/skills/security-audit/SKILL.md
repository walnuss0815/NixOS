---
name: security-audit
description: Use when asked to audit the security of a repository that deploys Kubernetes with GitOps (Argo CD, Flux) and Terraform/OpenTofu IaC, optionally including its live cluster, or to check such a repo for open CVEs, exposed components, tenant isolation gaps or OWASP Kubernetes / CI/CD Top 10 risks, with a written security audit report.
---

# Security audit

Audit a GitOps + Kubernetes + Terraform/OpenTofu repository and, only if the user enables it, the live setup it deploys. The output is one report file. The audit reads; it changes nothing except writing that report.

## Never

- Read, print or send secret values. Do not open `secrets.yaml`, `*.secrets.env`, `*.tfvars`, tfstate files, `.terraform/`, kubeconfig, talosconfig, Kubernetes Secret `data`, `.env` files. Report *that* and *where* a secret is exposed (path, line, type), never the value. Redact anything secret-like in tool output before it reaches the report.
- Run any command whose path arguments or globs can reach those paths. Enumerate files with `git ls-files` and search content with `git grep` (tracked files only); the redacting scanners in `checks/secrets.md` are the only tools that look at untracked files.
- Guess a version. A version you cannot find pinned in the repo goes under "Not checked".
- Mutate anything: no `tofu apply`, `tofu init`, `tofu plan -out=<repo path>`, `kubectl apply|create|patch|delete|edit|exec|port-forward`, `talosctl apply-config|upgrade|reset|edit|patch`, no state locks.
- Call GitHub/GitLab APIs outside the live phase, for any repository. Advisory data comes from the sources in `checks/cve.md` only.
- Put repo content into web searches or advisory queries. Only component names and versions leave the machine.
- Work around a sandbox denial (EACCES/EPERM) or a 401/403. List the item under "Not checked" with the reason.
- Report a finding without evidence: `path:line` for repo findings, the command and its (redacted) output for live findings.

## Workflow

1. **Scope.** Confirm the repo root. Ask with the question tool whether to run the live phase (default: no). If yes, ask which kubeconfig, talosconfig and IaC wrapper (e.g. `hack/tofu.sh`) to use; never open them.
2. **Stack detection.** Record in a short stack summary: GitOps tool (Argo CD, Flux), manifest tooling (Helm, Kustomize, Jsonnet, plain YAML), IaC (Terraform/OpenTofu, providers, modules, backend), cluster type (Talos, kubeadm, k3s, EKS/GKE/AKS), CI (GitHub Actions, GitLab CI), tenancy (Capsule, HNC, namespace-per-team, none), identity (OIDC issuers, IdPs). Read the repo's README, design docs and runbooks: every security assumption they state ("port X is firewalled", "only operators can ...") goes into an **assumptions list** for the checks to verify.
3. **Inventory.** List every component with its exact pinned version and where it is pinned (`path:line`): vendir locks, `Chart.yaml`/`Chart.lock`, image tags, `.terraform.lock.hcl`, module `ref=`, Talos/Kubernetes versions in IaC, `flake.lock`, Renovate config. If the repo has an offline render or check script that needs no credentials, run it to get rendered manifests and image tags. Rendering may fetch public chart and kustomize sources anonymously; never with credentials. A remote module or source you cannot fetch anonymously goes under "Not checked".
   **Vendored code:** audit what gets deployed, including vendored parts that are rendered into manifests. Tag such findings `Upstream: <owner/repo>`. Skip the vendored repo's own CI, docs and nested vendor trees, but keep its components in the inventory.
4. **Checks.** Choose the check files:

   | Check file | Run when |
   |---|---|
   | `checks/secrets.md` | always |
   | `checks/iac.md` | always |
   | `checks/gitops.md` | always |
   | `checks/supply-chain-ci.md` | always |
   | `checks/cve.md` | always |
   | `checks/k8s-rbac-tenancy.md` | Kubernetes manifests exist |
   | `checks/live.md` | the user enabled the live phase |

   Dispatch one subagent per chosen repo check file, all in one batch. Give each: the repo root, the stack summary, the assumptions list, the inventory, the absolute path of its check file and of `report-template.md`, and the **Never** list above verbatim. Each returns findings in the template's finding format plus its "Not checked" items. Without a subagent tool, work through the same check files yourself, one after another.
5. **Live phase** (only if enabled): after the repo checks, follow `checks/live.md` yourself, using the repo findings as hypotheses to confirm or refute.
6. **Report.** Merge: one finding per root cause (merge duplicates, keep all evidence), severity by impact in this setup (who can exploit it, what they get), OWASP IDs on every finding, coverage table complete, "Not checked" complete. Write it following `report-template.md` to `docs/security/YYYY-MM-DD-security-audit.md` in the audited repo. If that file exists, use `-2`, `-3`, ... — never overwrite. Do not commit. Reply with the report path and the top 5 findings.

## Severity

"Untrusted party" means the least trusted party that can reach the component in this setup: the internet, a tenant, or, for clusters on a private network, anyone on that network. State which one in each finding's Impact.

| Severity | Meaning in this setup |
|---|---|
| Critical | An unauthenticated untrusted party gets cluster-admin, node access, other tenants' data or secrets |
| High | An untrusted party crosses a tenant/platform boundary, or a pre-auth exploitable CVE is reachable by one |
| Medium | Boundary crossing needs a stolen operator credential or an extra precondition; exposure that widens attack surface |
| Low | Defense-in-depth gap with no known path today |
| Info | Hygiene, removable workarounds, notes |

## Common mistakes

- Only reading config and skipping the inventory and CVE lookup.
- Trusting a design doc or code comment that says something is closed, without checking the firewall/auth config it describes.
- Treating a documented workaround as still needed without checking whether the pinned version already fixes the CVE.
- Citing a file without a line.
- Reviewing vendored code only where a finding already points to it: rendered manifests from vendored code are deployed and are in scope.
