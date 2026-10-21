# alexander-pc2

Headless LLM server: [NInfer](https://github.com/Neroued/ninfer) serves
an abliterated (uncensored) Qwen3.8-27B NVFP4 model on the NVIDIA GPU
through an OpenAI-/Anthropic-compatible HTTP API. There is no desktop;
the host is administered over SSH only.

| | |
|---|---|
| Disk | single NVMe, LUKS2 + ext4, TPM2 unlock, Secure Boot (lanzaboote) |
| Login | `ssh alexander@<address>` (keys only, passwordless sudo) |
| Address | DHCP on the wired NIC |
| LLM service | `ninfer.service`, `http://<address>:8080`, starts at boot |
| LLM config | [`modules/system/ninfer/qwen3.8-27b.nix`](../../modules/system/ninfer/qwen3.8-27b.nix) |
| Model file | `/var/lib/ninfer/models/qwen3.8-27b-huihui-abliterated-nvfp4.ninfer` |
| API key file | `/var/lib/ninfer/api-key.txt` |
| Updates | nightly from `github:walnuss0815/NixOS/wip`, reboot 03:00-05:00 |

The model file and the API key are not managed by Nix and are placed by
hand after the install (step 6).

## 1. Firmware

In the BIOS/UEFI setup:

- UEFI-only boot (no CSM/legacy).
- Secure Boot in "Setup Mode" (clear the existing keys), but still
  disabled for now.
- AMD fTPM enabled (often "AMD fTPM switch" or "PSP fTPM").

A keyboard and monitor are needed until TPM2 unlock works (step 5);
before that every boot waits for the LUKS passphrase on the console.

## 2. Install NixOS (nixos-anywhere)

Boot the current NixOS minimal ISO from USB. In its console:

```sh
sudo mkdir -p /root/.ssh
curl -fsSL https://github.com/walnuss0815.keys | sudo tee /root/.ssh/authorized_keys
sudo systemctl start sshd
ip -br a   # note the DHCP address
```

If the installer gets no address: the onboard RTL8125 NIC may never
finish DHCP with the in-kernel `r8169` driver the installer uses. Use a
USB Ethernet adapter for the install; the installed system loads
Realtek's `r8125` driver instead (see `configuration.nix`).

From a checkout of this repository, choose the LUKS passphrase, store
it in the Bitwarden vault (it stays the fallback whenever TPM2 unlock
fails) and install:

```sh
(umask 077; read -rs 'pw?LUKS passphrase: ' && printf '%s' "$pw" > /tmp/alexander-pc2.key)
nix run github:nix-community/nixos-anywhere -- \
  --flake .#alexander-pc2 \
  --disk-encryption-keys /tmp/secret.key /tmp/alexander-pc2.key \
  --target-host root@<installer-address>
rm /tmp/alexander-pc2.key
```

(`read -rs 'pw?...'` is zsh; in bash use `read -rsp '...' pw`.)

This wipes `/dev/nvme0n1` (see [`disko.nix`](./disko.nix)), installs,
registers the firmware boot entry and reboots. Remove the USB stick.

## 3. First boot

Enter the LUKS passphrase on the console, then log in with
`ssh alexander@<address>`.

`hardware-configuration.nix` matches the generated configuration of this
machine (plus a hand-added swapfile). After hardware changes, compare it
with a freshly generated one and adjust if they differ:

```sh
nixos-generate-config --no-filesystems --show-hardware-config
```

`ninfer.service` fails and restarts every 10 seconds until the model
file and API key exist (step 6); that is expected.

## 4. Secure Boot

1. Reboot into the firmware setup (`systemctl reboot --firmware-setup`)
   and enable Secure Boot.
2. Boot NixOS. lanzaboote generated its keys on the first activation
   and the firmware enrolls them now, together with Microsoft's keys
   (the GPU's option ROM is signed with Microsoft's UEFI CA). Reboot
   once more.
3. Verify:

   ```sh
   sudo sbctl status
   sudo sbctl verify
   ```

## 5. TPM2 unlock

Only after Secure Boot is set up: the TPM2 keyslot is bound to PCR 7
(Secure Boot state), which step 4 changes.

```sh
sudo systemd-cryptenroll --tpm2-device=auto /dev/disk/by-partlabel/disk-main-cryptroot
```

Reboot and confirm the host comes up without the passphrase. The
passphrase keyslot stays as a fallback. Until this works, the nightly
update reboot leaves the host waiting at the LUKS prompt.

## 6. Model and API key

### Model

The model is
[`Barding-Defense/Qwen3.8-27B-huihui-abliterated-NVFP4-NInfer`](https://huggingface.co/Barding-Defense/Qwen3.8-27B-huihui-abliterated-NVFP4-NInfer),
an abliteration of the official `Qwen/Qwen3.8-27B`, already converted to
NInfer's NVFP4 format. It is published in NInfer's old container v2
format, which the current engine no longer loads, so it is upgraded to
v3 with NInfer's own tool after the download. The download and the
upgraded file each take about 21.5 GB, so `/var/tmp` needs about 43 GB
free.

On the host, download and verify:

```sh
mkdir -p /var/tmp/ninfer && cd /var/tmp/ninfer
nix-shell -p 'python3.withPackages (ps: [ ps.huggingface-hub ])' --run \
  'hf download Barding-Defense/Qwen3.8-27B-huihui-abliterated-NVFP4-NInfer \
     qwen3_8_27b_huihui_abliterated_nvfp4.ninfer --local-dir .'
stat -c %s qwen3_8_27b_huihui_abliterated_nvfp4.ninfer
# expect 21492695040
sha256sum qwen3_8_27b_huihui_abliterated_nvfp4.ninfer
# expect 02c0c80616e2dd353133355d840aa6418d83f4c523369ad93b426e6c5bbc83c8
```

Upgrade to v3 and check the result. The tools only need the Python
standard library; use the same NInfer commit the package in
[`pkgs/ninfer`](../../pkgs/ninfer/default.nix) is built from:

```sh
nix-shell -p git python3 --run '
  git clone https://github.com/Neroued/ninfer.git src &&
  git -C src checkout 1d8587bcfe850fba310d8833552f3c0c07e3a4bd &&
  python3 src/tools/upgrade_ninfer_v2_to_v3.py \
    qwen3_8_27b_huihui_abliterated_nvfp4.ninfer \
    qwen3.8-27b-huihui-abliterated-nvfp4.ninfer &&
  cd src && python3 -m tools.artifact.inspect \
    ../qwen3.8-27b-huihui-abliterated-nvfp4.ninfer'
```

Expect `version: 3`, `objects: 1124`, `name: qwen3.8-27b` and the
components `text`, `vision` and `mtp`. The tool reports `1 files`: it
only splits its output into `.part-NNNN` files above 32 GB.

The upgrade tool always creates its output with mode `0600`, owned by
the user who ran it, so the service could not open it (`open:
Permission denied` in the log). Make it world-readable, then move it
into place and clean up:

```sh
chmod 644 qwen3.8-27b-huihui-abliterated-nvfp4.ninfer
sudo mkdir -p /var/lib/ninfer/models
sudo mv qwen3.8-27b-huihui-abliterated-nvfp4.ninfer /var/lib/ninfer/models/
cd / && rm -rf /var/tmp/ninfer
```

`/var/tmp` and `/var/lib` are on the same filesystem, so the `mv` is
instant and keeps the mode.

### API key

Every request except `GET /health` needs this key as
`Authorization: Bearer <key>` (OpenAI) or `x-api-key: <key>`
(Anthropic). Generate it, store it in the Bitwarden vault as
`alexander-pc2-ninfer-key`, and never commit it:

```sh
nix-shell -p openssl --run 'openssl rand -base64 32' \
  | (umask 077; sudo tee /var/lib/ninfer/api-key.txt >/dev/null)
```

### Ownership

The service runs as a dynamic user (`DynamicUser`), and it reads the API
key itself, so the key file must be owned by that user with mode `600`.
A key created as root is not readable by the service.

`/var/lib/ninfer` is the unit's `StateDirectory`; systemd keeps it under
`/var/lib/private/ninfer` and symlinks it. On start, systemd only checks
the owner of that top-level directory: if it already belongs to the
service user, files created inside it later are left as they are. After
placing the files, hand everything to the directory's owner and restart:

```sh
sudo chown -R --reference=/var/lib/private/ninfer /var/lib/private/ninfer
sudo chmod 600 /var/lib/private/ninfer/api-key.txt
sudo systemctl restart ninfer
```

`--reference` copies the directory's numeric owner, so this also works
while the service is stopped and the dynamic user does not exist. The
result should look like this:

```sh
sudo ls -l /var/lib/private/ninfer /var/lib/private/ninfer/models
# -rw------- ninfer ninfer ... api-key.txt
# -rw-r--r-- ninfer ninfer ... qwen3.8-27b-huihui-abliterated-nvfp4.ninfer
```

`open: Permission denied` in `journalctl -u ninfer` means one of these
files is not readable by the service user.

## 7. Verify

```sh
sudo systemctl restart ninfer
journalctl -u ninfer -n 40 --no-pager
```

Look for `engine ready` and `listening on http://0.0.0.0:8080`. Loading
the model takes tens of seconds; `/health` only reports ok once the
engine accepts work.

```sh
curl http://127.0.0.1:8080/health
# {"status":"ok"}
curl -H "Authorization: Bearer $(sudo cat /var/lib/ninfer/api-key.txt)" \
  http://127.0.0.1:8080/v1/models
```

Repeat the authenticated request from another machine against
`http://<address>:8080` (port 8080 is open in the firewall).

## Tuning

The engine flags live in
[`modules/system/ninfer/qwen3.8-27b.nix`](../../modules/system/ninfer/qwen3.8-27b.nix)
and are shared with another host, where they were sized for a GPU that
also drives a desktop session. Here the whole GPU is free, so there is
likely room for a larger `--max-context` or `--max-concurrency`. To
change them for this host only, override `services.ninfer.extraFlags`
in `configuration.nix` (with `lib.mkForce`).

The `capacity |` line in the startup log shows how much VRAM is left
after weights and runtime reservation. If a value is too large, startup
fails with a line like:

```
FATAL server failed during startup | minimum Engine runtime reservation
requires N bytes in addition to M bytes of automatic headroom, but only
K bytes are available after weights
```

The runtime reservation grows roughly linearly with `--max-context`
(about 34 KB per token at `--max-concurrency 1`), which allows working
out a value that fits from those numbers. `--vision` is off on purpose:
its encoder workspace is large and does not shrink with
`--max-context`.

## Updates

The host pulls `github:walnuss0815/NixOS/wip` nightly at 03:00
(`system.autoUpgrade`) and reboots between 03:00 and 05:00 when the
kernel or driver changed. Unattended reboots only work once TPM2 unlock
is set up (step 5).

To deploy a change right away, from a checkout of this repository:

```sh
nixos-rebuild switch --flake .#alexander-pc2 \
  --target-host alexander@<address> --sudo
```
