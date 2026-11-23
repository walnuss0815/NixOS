# Check: live phase (opt-in)

Run only if the user enabled the live phase in `SKILL.md` step 1 and named the kubeconfig, talosconfig and IaC wrapper to use. Pass them by flag or environment variable (`--kubeconfig`, `--talosconfig`, `KUBECONFIG=`); never open or print them.

**Allowed:** `kubectl get|describe` (never on `secrets`), `kubectl auth can-i`, `kubectl version`, `talosctl get|version|health` on the resources below, `tofu plan -lock=false`, `nc`, read-only SCM API calls. **Everything else is forbidden.**

Each probe records the exact command and its redacted output as evidence. A denied path or credential (EACCES/EPERM, 401/403, missing file) puts that probe under **Not checked** with the reason; do not retry with other credentials or work around the sandbox.

## Probes

1. **Reachability** of every port in the exposure table from `iac.md`, from the audit host, per node IP: `nc -zv -w3 <ip> <port>`. Confirms or refutes each exposure finding.
2. **Effective permissions** for a representative low-trust identity (a tenant service account, a customer user, `system:anonymous`) and default service accounts:
   `kubectl auth can-i --list --as=<user> [--as-group=<group>] -n <namespace>`
3. **Live policy objects** vs repo: `kubectl get networkpolicies,ciliumnetworkpolicies,ciliumclusterwidenetworkpolicies -A`, `kubectl get validatingadmissionpolicies,validatingwebhookconfigurations,mutatingwebhookconfigurations`. Missing or extra objects are drift findings.
4. **Running versions** vs pins: `kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}{end}'`. Feed differing versions back into `cve.md`.
5. **Talos** (if used): `talosctl get machinestatus`, `talosctl get nodeaddresses`, `talosctl version`. Never `machineconfig`, `secrets`, `kubeconfig` or any resource holding keys.
6. **IaC drift:** `tofu plan -lock=false -detailed-exitcode` through the named wrapper, output to `/tmp/opencode/`. Never run `tofu init`; if the directory is not initialised, put drift under Not checked. Report only resource addresses and changed attribute names, never values.
7. **SCM settings** (GitHub/GitLab API, read-only): real branch protection or rulesets on the tracked branch, bypass actors, installed apps and their permissions, collaborators with admin rights, vulnerability alerts status. Compare with the committed config `gitops.md` reviewed.
