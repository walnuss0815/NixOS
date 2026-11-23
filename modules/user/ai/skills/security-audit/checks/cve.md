# Check: CVEs in pinned components

OWASP: K07 Misconfigured And Vulnerable Cluster Components, CICD-SEC-3 Dependency Chain Abuse.

Input: the inventory from `SKILL.md` step 3. Only component names and versions leave the machine.

## 1. Advisories per component

Query in this order and stop at the first source that knows the component:

1. **OSV.dev** (includes GitHub Security Advisories):

   ```bash
   curl -s -X POST https://api.osv.dev/v1/query \
     -d '{"package":{"name":"<module or package>","ecosystem":"<Go|npm|PyPI|Maven|...>"},"version":"<version>"}'
   ```

   Map components to their source package: Go projects to their Go module (e.g. `github.com/argoproj/argo-cd/v3`), Keycloak to Maven `org.keycloak:keycloak-services`. For images, use the upstream project, not the image name.
2. **Kubernetes feed** for Kubernetes itself (kube-apiserver, kubelet, ...): `https://kubernetes.io/docs/reference/issues-security/official-cve-feed/index.json`; match by affected version ranges in each entry.
3. **Vendor security pages and release notes** (GitHub Security tab, release notes between the pinned and the latest version) for components OSV doesn't know (e.g. Talos, some operators).

If a source is unreachable, rate-limited or returns an error for a component, list that component under **Not checked** with the reason. Never write "no CVEs" for a component you could not query.

## 2. Impact per CVE

For each advisory whose affected range includes the pinned version:

- **Feature used?** Is the vulnerable feature, endpoint or code path enabled in this repo's config? Cite `path:line`.
- **Who can reach it?** Internet (cross-check the exposure table from `iac.md`), tenant, operator only, nobody.
- **Mitigation?** Search commit messages and config for the CVE ID (`git log --all --oneline -i --grep=<CVE-ID>`, `grep -rn <CVE-ID>`). A mitigation counts only if its config is still present at HEAD.

Status, exactly one:

| Status | When |
|---|---|
| exploitable | affected, feature used, reachable by someone untrusted |
| mitigated | affected, but a workaround present at HEAD blocks it |
| not applicable | affected version, but feature not used or not reachable |
| fixed in pinned version | the pinned version is outside the affected range |

Severity in the report follows reachability: an exploitable CVE reachable by tenants or the internet is High or Critical regardless of CVSS; operator-only is at most Medium.

**Workaround removable:** for every CVE mentioned in commits or config, also check whether the pinned version still is affected. If it is not, add an Info finding "workaround removable" citing the workaround (`path:line` and commit) and the fixing version. Status in the CVE table: fixed in pinned version.

## 3. Container images (Trivy)

For each image in the inventory (rendered manifests, chart values, kustomize images):

```bash
mkdir -p /tmp/opencode/trivy-docker /tmp/opencode/trivy-cache
DOCKER_CONFIG=/tmp/opencode/trivy-docker nix shell nixpkgs#trivy -c trivy image \
  --cache-dir /tmp/opencode/trivy-cache --severity HIGH,CRITICAL --quiet \
  --format json --output /tmp/opencode/trivy-<n>.json <image:tag>
```

The empty `DOCKER_CONFIG` keeps Trivy away from the user's registry credentials; images are pulled anonymously.

Summarise per image: count of Critical and High, and up to three notable CVEs with fixed versions. An image that cannot be pulled (private registry, no credentials, rate limit) gets scan status "not scanned (<reason>)"; do not log in to registries. Trivy results go to the appendix only; promote a Trivy CVE to a finding only after the impact check in section 2.
