# Check: RBAC, policy, network segmentation and tenancy

OWASP: K01 Insecure Workload Configurations, K02 Overly Permissive Authorization Configurations, K04 Lack Of Cluster Level Policy Enforcement, K05 Missing Network Segmentation Controls.

Work from rendered manifests where the repo can render offline; otherwise from the sources. Include vendored charts that get deployed (tag `Upstream`).

## RBAC (K02)

- `ClusterRole`/`Role` rules with `*` verbs or resources, and the escalation verbs and resources: `escalate`, `bind`, `impersonate`, `create` on `pods` in privileged namespaces, `secrets` get/list/watch, `nodes/proxy`, `pods/exec|attach|portforward`, `serviceaccounts/token`, `certificatesigningrequests/approval`, `mutatingwebhookconfigurations`/`validatingwebhookconfigurations`, `networkpolicies` and CNI policy CRDs.
- Aggregated ClusterRoles (`aggregationRule`, `rbac.authorization.k8s.io/aggregate-to-*` labels): which CRD roles a vendored chart adds to `admin`/`edit`. Tenants that hold `admin` in their namespaces get those too.
- Bindings to broad groups: `system:authenticated`, `system:serviceaccounts`, IdP groups. Who can be in that group?
- Default service accounts: automounted tokens with roles.

## Policy enforcement (K04, K01)

- Admission: ValidatingAdmissionPolicy, Kyverno, Gatekeeper, Capsule, Pod Security Admission labels. Which namespaces are exempt?
- Workload settings on tenant-reachable or internet-facing workloads: privileged, `hostPath`, `hostNetwork`/`hostPID`, added capabilities, `runAsNonRoot`, `readOnlyRootFilesystem`, `automountServiceAccountToken`. Platform system components (CNI, CSI) needing privileges are Info unless tenants can influence them.

## Network segmentation (K05)

- Default-deny per namespace? Which namespaces have no policy?
- **Selector trust:** every NetworkPolicy/CNI policy `podSelector`/`namespaceSelector` that *allows* traffic based on labels a less trusted party can set. A tenant who controls pod labels in their namespace can add any label a platform policy matches on (e.g. an operator's pod label that opens API server or database egress). Report each such allow rule with the label it trusts.
- Egress from tenant pods to: API server, node ports (kubelet, etcd metrics), cloud metadata, platform namespaces, other tenants.
- Services without auth behind those paths (storage UIs, metrics endpoints, admin APIs).

## Tenancy (only if the stack summary lists tenancy)

- Namespace ownership and naming: can a tenant name or prefix collide with platform namespaces or another tenant's prefix?
- Quotas and limits: CPU, memory, pods, storage, object counts, ephemeral storage, PIDs.
- Hostnames and certificates: can a tenant claim another tenant's or a platform hostname on a shared Gateway/Ingress? Can a tenant create `Certificate`/`Issuer` objects or ACME challenges for names they don't own?
- Shared gateways: one tenant's bad route breaking others; listener isolation.
- Storage classes and LoadBalancer IP pools: which namespaces may use them?
- Identity: tenant group to tenant mapping comes from a claim the user cannot change.

Deep references, read only for detail: https://cheatsheetseries.owasp.org/cheatsheets/Multi_Tenant_Security_Cheat_Sheet.html, https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html
