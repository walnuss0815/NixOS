# Report template

Fill every section, in this order. Empty sections say "None" — never drop a section.

## Finding format

Each check returns findings in exactly this shape:

```markdown
### <ID>. <Title>

- **Severity:** Critical | High | Medium | Low | Info
- **OWASP:** K0x, CICD-SEC-x (at least one)
- **Upstream:** <owner/repo> (only for findings from vendored code)
- **Evidence:** `path:line` (repo) or the command and its redacted output (live); one bullet each
- **Impact:** who can exploit it here (internet / tenant / operator) and what they get
- **Fix:** the concrete change, with the file to change
```

IDs: `C1`, `H1`, `M1`, `L1`, `I1`, ... per severity, assigned at merge.

## Report

```markdown
# Security audit: <repo name>

- **Repository:** <path or URL>, commit <sha>
- **Date:** YYYY-MM-DD
- **Stack:** <stack summary, one line per layer>
- **Live phase:** ran | not run

## Summary

| Critical | High | Medium | Low | Info |
|---|---|---|---|---|
| n | n | n | n | n |

Top 5: one line each, ID and title.

## Findings

### Critical
### High
### Medium
### Low
### Info

## CVEs

| Component | Version | Pinned at | CVE | CVSS | Status | Reason | Fixed in |
|---|---|---|---|---|---|---|---|

Status is one of: exploitable, mitigated, not applicable, fixed in pinned version.

## Container images (Trivy)

| Image | Critical | High | Scan status |
|---|---|---|---|

Scan status: scanned, not scanned (<reason>).

## Coverage

| ID | Risk | Result |
|---|---|---|
| K01 | Insecure Workload Configurations | |
| K02 | Overly Permissive Authorization Configurations | |
| K03 | Secrets Management Failures | |
| K04 | Lack Of Cluster Level Policy Enforcement | |
| K05 | Missing Network Segmentation Controls | |
| K06 | Overly Exposed Kubernetes Components | |
| K07 | Misconfigured And Vulnerable Cluster Components | |
| K08 | Cluster To Cloud Lateral Movement | |
| K09 | Broken Authentication Mechanisms | |
| K10 | Inadequate Logging And Monitoring | |
| CICD-SEC-1 | Insufficient Flow Control Mechanisms | |
| CICD-SEC-2 | Inadequate Identity and Access Management | |
| CICD-SEC-3 | Dependency Chain Abuse | |
| CICD-SEC-4 | Poisoned Pipeline Execution | |
| CICD-SEC-5 | Insufficient PBAC (Pipeline-Based Access Controls) | |
| CICD-SEC-6 | Insufficient Credential Hygiene | |
| CICD-SEC-7 | Insecure System Configuration | |
| CICD-SEC-8 | Ungoverned Usage of 3rd Party Services | |
| CICD-SEC-9 | Improper Artifact Integrity Validation | |
| CICD-SEC-10 | Insufficient Logging and Visibility | |

Result: `findings: <IDs>`, `checked, none`, or `N/A (<reason>)`.

## Not checked

One bullet per item: what, and why (live phase off, access denied, source unreachable, image not pullable, ...).

Sources: https://github.com/OWASP/www-project-kubernetes-top-ten, https://owasp.org/projects/top-10-cicd-security-risks
```
