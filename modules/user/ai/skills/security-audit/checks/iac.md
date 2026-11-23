# Check: IaC exposure and cluster authentication

OWASP: K06 Overly Exposed Kubernetes Components, K07 Misconfigured And Vulnerable Cluster Components, K08 Cluster To Cloud Lateral Movement, K09 Broken Authentication Mechanisms.

## Exposure table

Build a table from node firewall rules (Talos `NetworkRuleConfig`, cloud security groups/firewalls, nftables), LoadBalancer Services and Ingress/Gateway listeners: `Port | Component | Open to (CIDRs) | Auth required | Evidence path:line`. Cover at least:

| Port | Component |
|---|---|
| 6443 | Kubernetes API |
| 50000 / 50001 | Talos apid / trustd |
| 22 | SSH (non-Talos) |
| 2379-2381 | etcd peers, clients, metrics |
| 10250 | kubelet |
| CNI ports (4240, 8472, 51871, ...) | Cilium/Calico/Flannel |
| WireGuard / KubeSpan (51820) | node mesh |
| 80 / 443 | edges, and which admin UIs they route to |

Anything open to `0.0.0.0/0` (or `::/0`) other than the public edge is a finding unless authentication is strong *and* the repo documents why. Also check pod CIDR access to node ports (kubelet, etcd metrics): any pod, including tenant pods, can reach those.

## Authentication of what is exposed

- **API server:** anonymous auth and its allowed paths; `AuthenticationConfiguration`/OIDC flags: issuers, audiences, claim mappings, username/group prefixes, CEL validation rules. For each issuer: who can obtain a token (customers? anyone who can self-register?) and with which audience. A token from a customer-facing realm that the API server accepts makes the API server customer-reachable.
- **Admin UIs on the edge:** GitOps UI, identity provider admin consoles (e.g. Keycloak `/admin/`), Grafana, storage UIs. Reachable from the internet? Which login protects them; is local password login still on?
- **Node API (Talos apid, SSH):** certificate-only vs password; who holds client certs.

## Drift against stated assumptions

For every item in the assumptions list from `SKILL.md` step 2 that concerns exposure or authentication ("6443 is firewalled", "only reachable from admin CIDRs"), compare with the config. A contradiction is a finding with *both* locations as evidence: the statement (`doc:line`) and the config (`config:line`). Severity follows what the wrong assumption enabled: designs built on it (token passthrough, skipped auth layers) inherit the exposure.

## Other IaC items

- Disk/volume encryption and where the key comes from (TPM, node ID, KMS).
- State backend: see `secrets.md`; here only provider credential scope (owner/admin vs least privilege) and whether CI holds them.
- Cloud IAM reachable from workloads (K08): instance metadata endpoints, workload identity bindings, node roles.
- Kubernetes and OS versions vs supported releases (K07); hand CVEs to `cve.md`.
