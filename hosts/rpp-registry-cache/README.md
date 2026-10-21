# rpp-registry-cache

Pull-through cache for container images, used by the self-hosted GitHub
Actions runners (`rpp-github-runner*`) so that E2E runs don't hit the
anonymous rate limits of the public registries. It runs
[zot](https://zotregistry.dev/) in an unprivileged LXC container on
server1 (Proxmox), set up with the
[community script](https://github.com/community-scripts/ProxmoxVE/blob/main/ct/zot-registry.sh).

This host is not managed by NixOS. This directory holds the zot
configuration ([`config.json`](./config.json)) and this runbook.

| | |
|---|---|
| Proxmox CT ID | 119 (unprivileged LXC, Debian) |
| Address | 192.168.13.11/24 (VLAN 130), gateway and DNS 192.168.13.254 |
| Resources | 2 cores, 4 GB RAM, 100 GB disk |
| Endpoint | `http://192.168.13.11:5000` (plain HTTP, LAN only) |
| Service | `zot.service`, config `/etc/zot/config.json`, data `/var/lib/zot` |

## What it caches

Images are fetched from the upstream on the first pull and then served
from the local disk. Each upstream has its own path prefix:

| Upstream | Path on the cache | Example |
|---|---|---|
| `docker.io` | `docker.io/` | `192.168.13.11:5000/docker.io/library/redis:8` |
| `public.ecr.aws` | `public.ecr.aws/` | `192.168.13.11:5000/public.ecr.aws/docker/library/redis:8` |
| `quay.io` | `quay.io/` | `192.168.13.11:5000/quay.io/prometheus/busybox:latest` |
| `ghcr.io` | `ghcr.io/` | `192.168.13.11:5000/ghcr.io/fluxcd/source-controller:v1.5.0` |
| `registry.k8s.io` | `registry.k8s.io/` | `192.168.13.11:5000/registry.k8s.io/pause:3.10` |

Behaviour, as set in [`config.json`](./config.json):

- All upstreams are accessed anonymously.
- Upstream media types and digests are kept unchanged; Docker schema 2
  images are accepted (`http.compat: ["docker2s2"]`).
- A cached tag is checked against the upstream at most once per hour
  (`manifestCheckInterval`); pulls by digest never go upstream once
  cached.
- Concurrent pulls of the same uncached image are fetched once.
- Anonymous clients can only read. Pushing needs the `admin` user from
  `/etc/zot/htpasswd`, which the install script creates (password in
  `/root/zot.creds`).
- Images that have been neither pulled nor fetched for 14 days are
  removed, together with unreferenced blobs, once a day.

Clients use it as a registry mirror. For containerd, a mirror for
`docker.io` looks like this (`/etc/containerd/certs.d/docker.io/hosts.toml`);
`override_path` is needed because of the path prefix:

```toml
server = "https://registry-1.docker.io"

[host."http://192.168.13.11:5000/v2/docker.io"]
  capabilities = ["pull", "resolve"]
  override_path = true
```

If the cache is down, containerd falls back to the upstream (`server`).

## 1. Create the container (Proxmox)

On server1, run the community script and choose **Advanced** settings:

```sh
var_cpu=2 var_ram=4096 var_disk=100 bash -c \
  "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/zot-registry.sh)"
```

Settings to use in the dialogs:

- Container type: unprivileged
- CT ID: `119`, hostname: `rpp-registry-cache`
- Disk: 100 GB, cores: 2, RAM: 4096 MB
- Bridge `vmbr0`, VLAN tag `130`
- IPv4: static `192.168.13.11/24`, gateway `192.168.13.254`, DNS
  `192.168.13.254`
- Start on boot: yes

The script installs the zot binary to `/usr/bin/zot`, a sample config
(registry with web UI on port 8080) and `zot.service`.

## 2. Apply the cache configuration

In the container (`pct enter 119`):

```sh
systemctl stop zot
curl -fsSLo /etc/zot/config.json \
  https://raw.githubusercontent.com/walnuss0815/NixOS/wip/hosts/rpp-registry-cache/config.json
mkdir -p /var/lib/zot
zot verify /etc/zot/config.json
systemctl start zot
journalctl -u zot -n 20
```

Repeat the `curl`/`verify`/restart steps after a change to
[`config.json`](./config.json).

## 3. Restrict access (Proxmox firewall)

The cache has no TLS and allows anonymous reads, so only the runner
VLAN may reach it. On server1, create `/etc/pve/firewall/119.fw`:

```ini
[OPTIONS]
enable: 1
policy_in: DROP

[RULES]
IN ACCEPT -source 192.168.13.0/24 -p tcp -dport 5000 -log nolog
```

and enable the firewall on the container's NIC (*CT 119 > Network >
net0 > Firewall*). The rules only take effect if the firewall is also enabled at
datacenter level (*Datacenter > Firewall > Options*). Administration
goes through `pct enter 119`, so SSH does not need to be reachable.

## 4. Check

From a runner (or any host in 192.168.13.0/24):

```sh
curl -s http://192.168.13.11:5000/v2/ -o /dev/null -w '%{http_code}\n'   # 200
nix run nixpkgs#crane -- manifest --insecure \
  192.168.13.11:5000/docker.io/library/busybox:latest | head -c 200; echo
curl -s http://192.168.13.11:5000/v2/_catalog
```

The catalog lists every cached repository with its upstream prefix.

## Updates

zot is not updated automatically. In the container:

```sh
update
```

The script's update replaces `/usr/bin/zot` with the latest release and
restarts the service; `/etc/zot/config.json` and the cached data are
kept. Check the [release notes](https://github.com/project-zot/zot/releases)
for config changes first, and run `zot verify /etc/zot/config.json`
afterwards. Debian packages are updated with `apt update && apt upgrade`.

## Troubleshooting

- Logs: `journalctl -u zot -f`. Upstream errors (e.g. 429) are logged by
  the sync extension with the requested repository.
- Disk usage: `du -sh /var/lib/zot`. To start from scratch, stop zot,
  remove `/var/lib/zot`, recreate it and start zot again; the cache
  refills on the next pulls.
- A pull that fails on the cache is retried by containerd against the
  upstream, so an outage of the cache only brings back the rate limits.
