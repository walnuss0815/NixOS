# Check: live phase (opt-in)

Run only if the user enabled the live phase in `SKILL.md` step 1 and named the kubeconfig, talosconfig and IaC wrapper to use. Pass them by flag or environment variable (`--kubeconfig`, `--talosconfig`, `KUBECONFIG=`); never open or print them.

**Allowed:** exactly the probe commands below with the output fields they show, `kubectl api-resources`, `kubectl version`, and read-only SCM API calls. **Everything else is forbidden**, in particular `-o yaml|json` and `describe` on secrets, configmaps, pods, Argo CD Applications, Flux HelmReleases/Kustomizations: those can print inlined secret values.

Each probe records the exact command and its redacted output as evidence. A denied path or credential (EACCES/EPERM, 401/403, missing file) puts that probe under **Not checked** with the reason; do not retry with other credentials or work around the sandbox.

## Probes

1. **Reachability** of every port in the exposure table from `iac.md`, from the audit host, per node IP: `nc -zv -w3 <ip> <port>`. Confirms or refutes each exposure finding.
2. **Effective permissions** for a representative low-trust identity (a tenant service account, a customer user, `system:anonymous`) and default service accounts:
   `kubectl auth can-i --list --as=<user> [--as-group=<group>] -n <namespace>`
3. **Live policy objects** vs repo: find the policy kinds the cluster has (`kubectl api-resources -o name | grep -i -e networkpolic -e admissionpolic -e webhookconfiguration -e clusterpolic`), then `kubectl get <kinds> -A` (names only, default output). Missing or extra objects are drift findings.
4. **Running versions** vs pins: `kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}{end}'`. Feed differing versions back into `cve.md`.
5. **Talos** (if used): `talosctl get machinestatus`, `talosctl get nodeaddresses`, `talosctl version`. Never `machineconfig`, `secrets`, `kubeconfig` or any resource holding keys.
6. **IaC drift:** `tofu plan` or `terraform plan` with `-lock=false -no-color -detailed-exitcode` through the named wrapper, redirected to `/tmp/opencode/plan.txt`; read only its action lines (`grep -E '^\s*# .* (will|must) be' /tmp/opencode/plan.txt`), never the attribute values. Never run `init`; if the directory is not initialised, put drift under Not checked. Report only resource addresses and actions.
7. **SCM settings** (GitHub/GitLab API, read-only): real branch protection or rulesets on the tracked branch, bypass actors, installed apps and their permissions, collaborators with admin rights, vulnerability alerts status. Compare with the committed config `gitops.md` reviewed.
