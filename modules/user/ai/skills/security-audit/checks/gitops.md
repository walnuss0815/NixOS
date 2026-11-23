# Check: GitOps trust

OWASP: K02 Overly Permissive Authorization Configurations, CICD-SEC-1 Insufficient Flow Control Mechanisms, CICD-SEC-2 Inadequate Identity and Access Management, CICD-SEC-4 Poisoned Pipeline Execution, CICD-SEC-5 Insufficient PBAC.

In GitOps the Git branch the controller tracks *is* the deployment pipeline. Read only what is committed; SCM API reads belong to `live.md`.

## Flow control (CICD-SEC-1)

- Which repo, branch and path does the controller track? Committed branch protection or rulesets (e.g. `.github/rulesets/*.json`, scripts that configure them): required reviews, status checks, bypass actors, force-push and deletion rules. A bypass that is the normal path for every merge is a finding.
- Who else writes to the tracked sources: vendored upstream repos, Helm repos, OCI registries, tenant repos.

## GitOps tool authorization (K02, CICD-SEC-2, -5)

- Argo CD: `argocd-rbac-cm` (`policy.default`, `g,` group mappings, `scopes`), `AppProject` `sourceRepos`, `destinations`, `clusterResourceWhitelist`/`Blacklist`, `namespaceResourceWhitelist`/`Blacklist`, `sourceNamespaces`, `destinationServiceAccounts` and `application.sync.impersonation.enabled`. Local `admin` account (`admin.enabled`) and other local accounts. Flux: `Kustomization`/`HelmRelease` `serviceAccountName`, `--default-service-account`, multi-tenancy lockdown flags, cross-namespace refs.
- Which identity becomes admin: an IdP group, a whole org/domain, or a claim users can set themselves (email, username)? Authorization on user-settable claims is a finding.
- Can a tenant project deploy cluster-scoped objects, or objects (NetworkPolicy, ResourceQuota, RoleBinding, Certificate, Gateway resources) that weaken its fence? Compare the blacklist with what the tenant's sync identity may create; a gap between the two is exploitable.

## Pipeline poisoning (CICD-SEC-4)

- Can a tenant or contributor get code executed with platform rights: config management plugins, Helm `lookup`, Jsonnet/Kustomize plugins, repo-server exec, CI that runs on PRs from forks?

## Credentials

- Repo credentials: how they are created (manual Secret, ESO, inline), their scope (read-only deploy keys vs personal tokens), and which projects may use them.
