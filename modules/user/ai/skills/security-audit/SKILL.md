---
name: security-audit
description: Use when asked to audit the security of a repository that deploys Kubernetes with GitOps (Argo CD, Flux) and Terraform/OpenTofu IaC, optionally including its live cluster, or to check such a repo for open CVEs, exposed components, tenant isolation gaps or OWASP Kubernetes / CI/CD Top 10 risks, with a written security audit report.
compatibility: Requires bash, git, curl, tar and network access; trivy and gitleaks are fetched if missing.
---

# Security audit

Audit a GitOps + Kubernetes + Terraform/OpenTofu repository and, only if the user enables it, the live setup it deploys. The output is one report file. The audit reads; it changes nothing except writing that report.

## Never

- Read, print or send secret values. Do not open `secrets.yaml`, `*.secrets.env`, `*.tfvars`, tfstate files, `.terraform/`, kubeconfig, talosconfig, Argo CD CLI config, `.env`, `.netrc`, `*.key`, `*.pem`, `*.agekey`, `credentials*.json`, Kubernetes Secret `data`, or any file a secret scanner flagged. Report *that* and *where* a secret is exposed (path, line, type), never the value. Redact anything secret-like in tool output before it reaches the report.
- Run any command whose path arguments or globs can reach those paths. Enumerate files with `git ls-files` and search content with `git grep` (tracked files only); the redacting scanners in `checks/secrets.md` are the only tools that look at untracked files.
- Guess a version. A version you cannot find pinned in the repo goes under "Not checked".
- Mutate anything: no `tofu`/`terraform` `apply|destroy|init|import|state|force-unlock|plan -out=<repo path>`, `kubectl apply|create|patch|delete|edit|exec|port-forward`, `talosctl apply-config|upgrade|reset|edit|patch`, no state locks.
- Log in anywhere: no `docker login`, `podman login`, `trivy registry login`. Existing registry logins are used only by `scripts/scan-images.sh`.
- Install tools system-wide or with a package manager. Get every tool through `scripts/tool.sh`.
- Touch a cluster, node, cloud API or state backend unless the live phase is enabled, even if credentials are in the environment. Exception: image pulls by `scripts/scan-images.sh`, including credential helpers configured in the user's Docker/Podman login files and Trivy's built-in ECR/GCR/ACR credential lookup (default AWS/Google/Azure credentials, sent only to that cloud's registry).
- Call GitHub/GitLab APIs outside the live phase, for any repository. Advisory data comes from the sources in `checks/cve.md` only. Exceptions: `scripts/tool.sh` reading `github.com/<repo>/releases.atom` and release files, and `GITHUB_TOKEN` used for `ghcr.io` image pulls.
- Put repo content into web searches or advisory queries. Only component names and versions leave the machine.
- Work around a sandbox denial (EACCES/EPERM) or a 401/403. List the item under "Not checked" with the reason.
- Report a finding without evidence: `path:line` for repo findings, the command and its (redacted) output for live findings.

## Workflow

1. **Scope.** Confirm the repo root. Ask with the question tool whether to run the live phase (default: no). If yes, ask which kubeconfig, talosconfig and IaC wrapper (e.g. `hack/tofu.sh`) to use; never open them. Create the work dir for all audit output: `mkdir -p /tmp/opencode/security-audit && mktemp -d /tmp/opencode/security-audit/<repo-name>.XXXXXX`; `<work>` below is that path, `<skill-dir>` the absolute base directory of this skill.
2. **Stack detection.** Record in a short stack summary: GitOps tool (Argo CD, Flux), manifest tooling (Helm, Kustomize, Jsonnet, plain YAML), IaC (Terraform/OpenTofu, providers, modules, backend), cluster type (Talos, kubeadm, k3s, EKS/GKE/AKS), CI (GitHub Actions, GitLab CI), tenancy (Capsule, HNC, namespace-per-team, none), identity (OIDC issuers, IdPs). Read the repo's README, design docs and runbooks: every security assumption they state ("port X is firewalled", "only operators can ...") goes into an **assumptions list** for the checks to verify.
3. **Inventory.** List every component with its exact pinned version and where it is pinned (`path:line`): vendir locks, `Chart.yaml`/`Chart.lock`, image tags, `.terraform.lock.hcl`, module `ref=`, Talos/Kubernetes versions in IaC, `flake.lock`, Renovate config. If the repo has an offline render or check script, read it first; run it only if it writes nothing outside `/tmp`, reads no gitignored files and needs no credentials. Compare `git status --porcelain` before and after: any change means stop and report it. Rendering may fetch public chart and kustomize sources anonymously; never with credentials. Render into `<work>/rendered/`; rendering tools (`helm`, `kustomize`, `jsonnet`, `vendir`) come from `tool.sh`, and a missing one puts that rendering under "Not checked". A remote module or source you cannot fetch anonymously goes under "Not checked".
   **Misconfiguration scan:** export the tracked files and scan them and the rendered manifests; the template keeps only ID, severity, title, file and line, never code:

   ```bash
   mkdir -p <work>/src && git archive HEAD | tar -x -C <work>/src
   "$(bash <skill-dir>/scripts/tool.sh trivy)" config --cache-dir <work>/trivy-config-cache --quiet \
     --format template --template "@<skill-dir>/scripts/trivy-misconfig.tpl" --output <work>/trivy-config.tsv <work>/src
   ```

   Repeat with `<work>/rendered` into `<work>/trivy-config-rendered.tsv`. Hand both files to the `iac` and `k8s-rbac-tenancy` subagents as leads: a lead becomes a finding only after the check confirms it.
   **Vendored code:** audit what gets deployed, including vendored parts that are rendered into manifests. Tag such findings `Upstream: <owner/repo>`. Skip the vendored repo's own CI, docs and nested vendor trees, but keep its components in the inventory.
4. **Checks.** Choose the check files:

   | Check file | Run when |
   |---|---|
   | `checks/secrets.md` | always |
   | `checks/iac.md` | always |
   | `checks/gitops.md` | always |
   | `checks/supply-chain-ci.md` | always |
   | `checks/cve.md`, part cve-components | always |
   | `checks/cve.md`, part cve-images | always |
   | `checks/k8s-rbac-tenancy.md` | Kubernetes manifests exist |
   | `checks/live.md` | the user enabled the live phase |

   Dispatch one subagent per chosen row (the two CVE parts are two subagents, each told its part), all in one batch. Give each: the repo root, `<work>` and `<skill-dir>` as absolute paths, the stack summary, the assumptions list, the inventory, the absolute path of its check file and of `report-template.md`, and the **Never** list above verbatim. Each subagent writes everything it found to `<work>/results/<check>.md` (`<check>` = the check file's name or the CVE part's name): findings in the template's finding format, its "Not checked" items, and any table rows it owns (CVE, image, exposure table). Its reply is at most about 15 lines and holds only: the path of that file, the count of findings per severity and of "Not checked" items, and its top 3 findings, one line each (title, severity, `path:line`). The findings themselves are never repeated in the reply. Without a subagent tool, work through the same check files yourself, one after another, writing the same files.
5. **Live phase** (only if enabled): after the repo checks, follow `checks/live.md` yourself, using the repo findings as hypotheses to confirm or refute.
6. **Report.** Read the files in `<work>/results/` and merge them: one finding per root cause (merge duplicates, keep all evidence), severity by impact in this setup (who can exploit it, what they get), OWASP IDs on every finding, coverage table complete, "Not checked" complete. Write it following `report-template.md` to `docs/security/YYYY-MM-DD-security-audit.md` in the audited repo. The image CVE details go to a second file with the same name plus `-image-cves` (e.g. `docs/security/YYYY-MM-DD-security-audit-image-cves.md`). Use the first suffix (none, `-2`, `-3`, ...) for which **both** files are free — never overwrite either. Write the details file unread; `set -C` makes the shell refuse to overwrite:

   ```bash
   (set -C; { echo "# Image CVE details: <repo name>, YYYY-MM-DD, commit <sha>"; echo; cat <work>/trivy/fixes.md; } > <details file>)
   ```

   The report's `## Image CVE details` section links that file and gives its row count (`tail -n +2 <work>/trivy/fixes.tsv | wc -l`). If the image scan failed (no `fixes.md`), write "Not scanned: <reason>" there and create no second file. Do not commit.
7. **Clean up.** Delete the work dir: `rm -r <work>` (if denied: `find <work> -delete`). Delete nothing else: `/tmp/opencode/trivy-cache` and `/tmp/opencode/tools` are reused by later audits. Reply with the report path, the details file path and the top 5 findings.

## Scripts

Call them as `bash <skill-dir>/scripts/<name>`, in the foreground; `--help` shows the interface.

| Script | Purpose | Output |
|---|---|---|
| `tool.sh <name>` | Path of `trivy`, `gitleaks`, `jq`, `yq`, `python3`, `helm`, `kustomize`, `jsonnet`, `vendir`, `zizmor`: from PATH, Nix, or (trivy, gitleaks, jq) a checked release download | path on stdout; exit 1 means not available, list it under "Not checked" |
| `advisories.sh <components.tsv> <out-dir>` | OSV advisories for every inventory component in one batch, with fixed versions and workaround text | `advisories.tsv`, `unknown.tsv`, `errors.tsv` in `<out-dir>`; see `checks/cve.md` section 1 |
| `scan-images.sh <list> <out-dir>` | Vulnerability scan of all images through one local Trivy server; uses existing Docker/Podman logins; one scan at a time across audits | `summary.tsv`, `fixes.tsv`, `fixes.md` in `<out-dir>`; set the shell timeout to `0`, it may wait for another audit |

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
- Querying OSV per component or writing advisory scrapers by hand: use `advisories.sh` for everything OSV knows; scrape vendor pages only for `unknown.tsv`.
- Running Trivy yourself, especially several at once: they block each other on the cache lock. Use `scan-images.sh`.
- Reading raw Trivy JSON or all of `fixes.tsv`: it can hold thousands of rows. Read `summary.tsv` and `grep`/`awk` slices.
- Calling a script with the shell tool's default 2-minute timeout: the call gets cancelled mid-scan.
- Writing audit output anywhere but `<work>`, or leaving `<work>` behind.
