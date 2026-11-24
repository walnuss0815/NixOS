# Check: CVEs in pinned components

OWASP: K07 Misconfigured And Vulnerable Cluster Components, CICD-SEC-3 Dependency Chain Abuse.

Input: the inventory from `SKILL.md` step 3. Only component names and versions leave the machine.

## 1. Advisories per component

Query in this order and stop at the first source that knows the component. OSV "knows" a package when a query for it *without* a version returns at least one advisory; an empty result with a version from a known package means no advisories for that version, an empty result for an unknown package means go to the next source:

1. **OSV.dev** (includes GitHub Security Advisories):

   ```bash
   curl -s -X POST https://api.osv.dev/v1/query \
     -d '{"package":{"name":"<module or package>","ecosystem":"<Go|npm|PyPI|Maven|...>"},"version":"<version>"}'
   ```

   Map components to their source package: Go projects to their Go module (e.g. `github.com/argoproj/argo-cd/v3`), Keycloak to Maven `org.keycloak:keycloak-services`. For images, use the upstream project, not the image name.
2. **Kubernetes feed** for Kubernetes itself (kube-apiserver, kubelet, ...): `https://kubernetes.io/docs/reference/issues-security/official-cve-feed/index.json`; match by affected version ranges in each entry.
3. **Vendor security pages and release notes** (web pages such as `github.com/<org>/<repo>/security/advisories` and `/releases`, never `api.github.com`; release notes between the pinned and the latest version) for components OSV doesn't know (e.g. Talos, some operators).

If a source is unreachable, rate-limited or returns an error for a component, list that component under **Not checked** with the reason. Never write "no CVEs" for a component you could not query.

## 2. Impact per CVE

For each advisory whose affected range includes the pinned version:

- **Feature used?** Is the vulnerable feature, endpoint or code path enabled in this repo's config? Cite `path:line`.
- **Who can reach it?** Internet (cross-check the exposure table from `iac.md`), tenant, operator only, nobody.
- **Mitigation applied?** Search commit messages and config for the CVE ID (`git log --all --oneline -i --grep=<CVE-ID>`, `git grep -n <CVE-ID>`). A mitigation counts only if its config is still present at HEAD.
- **Mitigation available?** Read the advisory's workaround section (the OSV/GHSA `details` text, usually headed "Workarounds", or the vendor advisory). Record the workaround in one line, or `none published`.
- **Fixed in:** the first release outside the affected range, `not available yet` if the advisory lists no fixed version, or `none planned (end of life)` if the vendor says so.

Status, exactly one:

| Status | When |
|---|---|
| exploitable | affected, feature used, reachable by someone untrusted |
| mitigation applied | affected, but a workaround present at HEAD blocks it |
| not applicable | affected version, but feature not used or not reachable |
| fixed in pinned version | the pinned version is outside the affected range |

Severity in the report follows reachability: an exploitable CVE reachable by an untrusted party (see Severity in `SKILL.md`) is High or Critical regardless of CVSS; operator-only is at most Medium.

**Workaround removable:** for every CVE mentioned in commits or config, also check whether the pinned version still is affected. If it is not, add an Info finding "workaround removable" citing the workaround (`path:line` and commit) and the fixing version. Status in the CVE table: fixed in pinned version.

## 3. Container images (Trivy)

Write every image in the inventory (rendered manifests, chart values, kustomize images), one reference per line, to `<work>/images.txt`. Then run, in the foreground with the shell tool's timeout set to `0` (the scan can take long and may first wait for another audit's scan):

```bash
bash <skill-dir>/scripts/scan-images.sh <work>/images.txt <work>/trivy
```

Never run Trivy for images yourself: parallel Trivy processes block each other on the cache lock.

Read `<work>/trivy/summary.tsv` (status and Critical/High/Medium/Low/fixable counts per image) for the image table. Look into `<work>/trivy/fixes.tsv` only with `grep`/`awk` slices, e.g. one image or one CVE; never read `raw/` or the whole file. `fixes.md` is appended to the report unread (`SKILL.md` step 6). Images with status `not scanned (<reason>)` go under "Not checked" with that reason.

Promote a Trivy CVE to a finding only after the impact check in section 2.
