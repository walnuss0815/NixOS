# Check: secrets

OWASP: K03 Secrets Management Failures, CICD-SEC-6 Insufficient Credential Hygiene, K08 Cluster To Cloud Lateral Movement.

Never open the files listed under **Never** in `SKILL.md`. You may test *whether* they exist, are ignored and are tracked (`git check-ignore -v`, `git ls-files`), never what they contain.

## Scanners

Run both with redaction; keep only rule ID, file, line and commit in your notes:

```bash
nix shell nixpkgs#gitleaks -c gitleaks git --redact --no-banner --report-format json --report-path /tmp/opencode/gitleaks-git.json <repo>
nix shell nixpkgs#gitleaks -c gitleaks dir --redact --no-banner --report-format json --report-path /tmp/opencode/gitleaks-dir.json <repo>
```

`gitleaks dir` also sees gitignored local files: report those as "present on the workstation" (Low unless world-readable or synced), not as committed. A match in git history counts as exposed even if a later commit removed it: the fix is rotation, not deletion.

## What to check

- **Ignore coverage:** state (`*.tfstate*`), `*.tfvars`, `.terraform/`, Talos `secrets.yaml`/`talosconfig`, `kubeconfig`, `.env`, dynamic/local config files the docs name as secret. Each must be gitignored *and* untracked.
- **IaC state:** backend type, encryption (OpenTofu native state encryption, bucket encryption), who can read the bucket, whether the passphrase or key lives next to the state.
- **Secrets in GitOps specs:** values inlined in Argo CD `Application`/`ApplicationSet` Helm values, Flux `HelmRelease` values, Jsonnet/Kustomize literals, ConfigMaps — versus `secretRef`/`valuesFrom`/`existingSecret`. Inlined values land in the GitOps tool's state and UI.
- **Secret delivery:** SOPS, Sealed Secrets, External Secrets, secretgen or manual `kubectl apply`. Manual steps in runbooks that put secrets in shell history or command lines.
- **Long-lived cloud credentials in the cluster** (K08): static service-account keys, S3 keys, DNS-01 credentials. For each: scope of its role, which namespaces hold a copy, rotation. A key that can change DNS records or read backups is a lateral movement path.
- **Generated secrets:** strength and where they are stored (e.g. Terraform `random_password` lands in state).
