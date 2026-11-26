# Check: CVEs in pinned components

OWASP: K07 Misconfigured And Vulnerable Cluster Components, CICD-SEC-3 Dependency Chain Abuse.

Input: the inventory from `SKILL.md` step 3. Only component names and versions leave the machine.

This check runs as two parallel subagents. Each does only its part:

| Part | Runs | Results file | Owns |
|---|---|---|---|
| **cve-components** | sections 1 and 2 | `<work>/results/cve-components.md` | CVE table, "workaround removable" findings |
| **cve-images** | sections 3 and 2 | `<work>/results/cve-images.md` | image table |

cve-images skips a Trivy CVE only if Trivy's package name and installed version exactly match a `package`/`version` row of `<work>/components.tsv` (written by cve-components; read it after your scan): cve-components covers those. If the file doesn't exist yet or nothing matches exactly, keep the CVE.

## 1. Advisories per component

Query in this order and stop at the first source that knows the component:

1. **OSV.dev** (includes GitHub Security Advisories). Write every component to `<work>/components.tsv`, one per line, tab-separated: `component	ecosystem	package	version` (OSV ecosystem names: `Go`, `npm`, `PyPI`, `Maven`, ...). Map components to their source package: Go projects to their Go module (e.g. `github.com/argoproj/argo-cd/v3`), Keycloak to Maven `org.keycloak:keycloak-services`; for images, the upstream project, not the image name. Then run once for the whole inventory, instead of querying OSV by hand:

   ```bash
   bash <skill-dir>/scripts/advisories.sh <work>/components.tsv <work>/osv
   ```

   - `advisories.tsv`: every advisory affecting the pinned version, with aliases (CVE IDs), severity, fixed versions of that package and the advisory's workaround text. These are the input for section 2.
   - `unknown.tsv`: OSV has no advisories for that package at any version. A package name that looks wrong (no advisories for a well-known project) is a mapping mistake: fix the row and re-run, already fetched advisories are reused. Otherwise triage by `github_advisories` (the repo's own published GitHub advisories):

     | `github_advisories` | Action |
     |---|---|
     | `0` | No published advisories: CVE `none`, no further research, but only if `<owner>/<repo>` is the project's canonical repo (not a fork or mirror). Exception: if the project's `SECURITY.md` or README names another place for advisories (own website, mailing list), check that instead. |
     | `N` or `N+` | Review only the listed `ids` (and, for `N+`, further pages of `github.com/<owner>/<repo>/security/advisories`): those published after the pinned version, plus any older one whose patched version is newer than the pinned one or missing. |
     | `n/a` | No GitHub repo derivable: source 2 or 3. |
     | `error` | Page didn't load: re-run once, then **Not checked**. |
   - `errors.tsv` and exit code 3 (OSV unreachable): list under **Not checked**. Exit code 2 names the inventory line OSV rejected: fix it and re-run.
   - A component in none of the three files was checked: OSV knows the package and lists no advisory for that version (CVE table row with CVE `none`).

   Read `advisories.tsv` with `grep`/`awk` slices per component. A "fixed" value that is a Go pseudo-version or an empty one with a `GO-` ID can mean OSV matched the module path loosely: confirm against the vendor advisory before reporting.
2. **Kubernetes feed** for Kubernetes itself (kube-apiserver, kubelet, ...): `https://kubernetes.io/docs/reference/issues-security/official-cve-feed/index.json`; match by affected version ranges in each entry.
3. **Vendor security pages and release notes** (web pages such as `github.com/<org>/<repo>/security/advisories` and `/releases`, never `api.github.com`; release notes between the pinned and the latest version) for components OSV doesn't know and `unknown.tsv` can't settle (software without an ecosystem package such as nginx, HAProxy, Redis, PostgreSQL). Read advisories newest first: those published after the pinned version was released, plus any older one whose patched version is newer than the pinned one or missing.

If a source is unreachable, rate-limited or returns an error for a component, list that component under **Not checked** with the reason. Never write "no CVEs" for a component you could not query.

## 2. Impact per CVE

For each advisory whose affected range includes the pinned version:

- **Feature used?** Is the vulnerable feature, endpoint or code path enabled in this repo's config? Cite `path:line`.
- **Who can reach it?** Internet (cross-check the exposure table from `iac.md`), tenant, operator only, nobody.
- **Mitigation applied?** Search commit messages and config for the CVE ID (`git log --all --oneline -i --grep=<CVE-ID>`, `git grep -n <CVE-ID>`). A mitigation counts only if its config is still present at HEAD.
- **Mitigation available?** For OSV advisories, the `workaround` column of `advisories.tsv` holds the advisory's Workarounds/Mitigation text; otherwise read the vendor advisory. An empty column means none found by the script, not proof that none exists: for exploitable or High/Critical CVEs read the advisory page before writing `none published`. Record the workaround in one line, or `none published` (also when the text only says there is none).
- **Fixed in:** the first release outside the affected range, `not available yet` if the advisory lists no fixed version, or `none planned (end of life)` if the vendor says so.

Status, exactly one:

| Status | When |
|---|---|
| exploitable | affected, feature used, reachable by someone untrusted |
| mitigation applied | affected, but a workaround present at HEAD blocks it |
| not applicable | affected version, but feature not used or not reachable |
| fixed in pinned version | the pinned version is outside the affected range |

Severity in the report follows reachability: an exploitable CVE reachable by an untrusted party (see Severity in `SKILL.md`) is High or Critical regardless of CVSS; operator-only is at most Medium.

**Workaround removable** (cve-components only): for every CVE mentioned in commits or config, also check whether the pinned version still is affected. If it is not, add an Info finding "workaround removable" citing the workaround (`path:line` and commit) and the fixing version. Status in the CVE table: fixed in pinned version.

## 3. Container images (Trivy)

Write every image in the inventory (rendered manifests, chart values, kustomize images), one reference per line, to `<work>/images.txt`. Then run, in the foreground with the shell tool's timeout set to `0` (the scan can take long and may first wait for another audit's scan):

```bash
bash <skill-dir>/scripts/scan-images.sh <work>/images.txt <work>/trivy
```

Never run Trivy for images yourself: parallel Trivy processes block each other on the cache lock.

If the script exits non-zero (1: trivy not available, 3: Trivy server did not start), no image was scanned: list every image under "Not checked" with the reason from stderr, and write "Not scanned: <reason>" for the Image CVE details section to your results file. Never report "none" for images that were not scanned.

Read `<work>/trivy/summary.tsv` (status and Critical/High/Medium/Low/fixable counts per image) for the image table. Look into `<work>/trivy/fixes.tsv` only with `grep`/`awk` slices, e.g. one image or one CVE; never read `raw/` or the whole file. `fixes.md` becomes the separate image CVE details file unread (`SKILL.md` step 6). Images with status `not scanned (<reason>)` go under "Not checked" with that reason.

Promote a Trivy CVE to a finding only after the impact check in section 2.
