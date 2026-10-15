# rpp-github-runner2

Self-hosted GitHub Actions runner for the
[RocketPadPlatforms](https://github.com/RocketPadPlatforms) org, running
as a VM on server1 (Proxmox).

| | |
|---|---|
| Proxmox VMID | 121 |
| Address | 192.168.13.13/24 (VLAN 130), gateway and DNS 192.168.13.254 |
| Runner name | `rpp-github-runner2` (labels `self-hosted`, `Linux`, `X64`) |
| Runner service | `github-runner-rpp.service` |

Runner, Docker and update settings are shared by all runner hosts and
live in [`modules/system/github-runner`](../../modules/system/github-runner/default.nix).

## 1. Create the VM (Proxmox)

The VM is created manually. Upload the current NixOS minimal ISO
(`nixos-minimal-*-x86_64-linux.iso`) to `local-btrfs`, then create the
VM in the UI or on server1 with:

```sh
qm create 121 \
  --name rpp-github-runner2 \
  --ostype l26 \
  --cpu host \
  --cores 4 \
  --memory 16384 \
  --balloon 8192 \
  --scsihw virtio-scsi-single \
  --scsi0 local-btrfs:128,iothread=1,discard=on,ssd=1 \
  --net0 virtio,bridge=vmbr0,tag=130 \
  --agent enabled=1 \
  --ide2 local-btrfs:iso/<nixos-minimal-iso>,media=cdrom \
  --boot 'order=scsi0;ide2' \
  --onboot 1
qm start 121
```

Notes:

- BIOS stays at the default SeaBIOS (no EFI disk, no Secure Boot);
  the disk layout in [`disko.nix`](./disko.nix) expects legacy boot.
- The disk must be on the VirtIO SCSI controller (`scsi0`), it shows
  up as `/dev/sda`, which is what [`disko.nix`](./disko.nix) targets.
- CPU type `host` is needed for nested containers to perform well.
- `--balloon 8192` lets the host reclaim memory from an idle runner
  (16 GB maximum, 8 GB minimum); all runners at full size plus the
  other VMs would exceed server1's RAM.

## 2. Install NixOS (nixos-anywhere)

The installer gets an address by DHCP on VLAN 130. In the VM console:

```sh
sudo mkdir -p /root/.ssh
curl -fsSL https://github.com/walnuss0815.keys | sudo tee /root/.ssh/authorized_keys
sudo systemctl start sshd
ip -br a   # note the DHCP address
```

From a checkout of this repository:

```sh
nix run github:nix-community/nixos-anywhere -- \
  --flake .#rpp-github-runner2 \
  --target-host root@<dhcp-address>
```

This partitions `/dev/sda` (destructive), installs and reboots. Remove
the ISO from the VM afterwards. The host then comes up on
192.168.13.13; log in with `ssh alexander@192.168.13.13`.

## 3. Register the runner

The runner registers itself on its first start, using a token from
`/var/lib/secrets/github-runner.token`. Create a registration token
(valid for one hour), either in the org settings under
*Actions > Runners > New runner* (the value after `--token`), or with:

```sh
gh api -X POST orgs/RocketPadPlatforms/actions/runners/registration-token --jq .token
```

Place it without a trailing newline and start the runner:

```sh
printf '%s' '<token>' | ssh alexander@192.168.13.13 \
  'sudo install -m 600 /dev/stdin /var/lib/secrets/github-runner.token'
ssh alexander@192.168.13.13 'sudo systemctl restart github-runner-rpp'
```

Check that it is online:

```sh
ssh alexander@192.168.13.13 'journalctl -u github-runner-rpp -n 20'
```

The token is only needed again when the runner has to register again:
when the token file's content or one of the registration settings
(name, labels, URL, work directory) changes, or after a reinstall. Put a
fresh token in place before deploying such a change.

## Updates

The host pulls `github:walnuss0815/NixOS/wip` nightly at 03:00
(`system.autoUpgrade`) and reboots between 03:00 and 05:00 when the
kernel changed. The runner and Docker are not restarted by the switch
itself, so a running job is not interrupted; a new runner version takes
effect on the next reboot or with
`sudo systemctl restart github-runner-rpp`.

To deploy a change right away:

```sh
nixos-rebuild switch --flake .#rpp-github-runner2 \
  --target-host alexander@192.168.13.13 --sudo
```

This does not restart the runner. To also restart it once no job is
running, and check the result, use the deploy script (it handles one or
more hosts, one after the other):

```sh
modules/system/github-runner/deploy.sh rpp-github-runner2
```
