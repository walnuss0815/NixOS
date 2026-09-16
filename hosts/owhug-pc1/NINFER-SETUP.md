# owhug-pc1 — NInfer local LLM setup

How `services.ninfer` (see `./configuration.nix` and
`../../modules/system/ninfer/default.nix`) got from nothing to a working
local LLM server on this host. If this file and the module/host comments
ever disagree, the `.nix` files are the source of truth.

Serving: Qwen3.8-27B, NVFP4 + FP8 text weights + the official DFlash2
speculative drafter, at `qwen3.8-27b`. Vision is disabled (see "Why vision
is off" below). Native context is 262,144 tokens; this deployment serves
196,608 (see "Why not full context" below).

## What actually happened (short version)

1. `pkgs/ninfer/default.nix` builds the engine (`ninfer`/`ninfer-serve`)
   from source, pinned to a specific commit, using `cudaPackages_13_1`
   (nixpkgs' default `cudaPackages` was 12.9; upstream's own measurements
   target CUDA 13.1 for `sm_120a`/RTX 5090).
2. Rather than the ~80GB multi-source download + local weight conversion
   originally planned (official BF16 checkpoint + NVFP4 quantized weights
   + DFlash2 drafter, combined via `tools/convert`), a single pre-built
   artifact already bundles the exact target combination:
   [`neroued/Qwen3.8-27B-nvfp4-NInfer`](https://huggingface.co/neroued/Qwen3.8-27B-nvfp4-NInfer)
   (22.09 GiB, `qwen3_8_27b_nvfp4.ninfer`, sha256
   `74d2c57145e6ff11d1d2faa79594477f9bc903a611af1fb20218189fbbb77d82`).
   It contains NVFP4/FP8 text, Vision, MTP, and the complete DFlash2
   companion weights, in v3 container format, publicly downloadable
   without auth. This eliminated the RAM risk, calibration-file ambiguity,
   and CUDA-toolkit-for-conversion questions the original plan carried.
3. Downloaded via `hf download neroued/Qwen3.8-27B-nvfp4-NInfer
   qwen3_8_27b_nvfp4.ninfer --local-dir <scratch>` (ephemeral
   `nix-shell -p 'python313.withPackages(ps: [ps.huggingface-hub])'` since
   `hf` isn't a system package), verified by size and sha256 against the
   published values, then installed to
   `/var/lib/ninfer/models/qwen3.8-27b-nvfp4-vision-dflash2.ninfer`
   (`sudo install -Dm644 ...`).
4. API key: `nix-shell -p openssl --run "openssl rand -base64 32"`,
   written to `/var/lib/ninfer/api-key.txt` (600, root-owned) and to an
   untracked `~/.secrets/owhug-pc1-ninfer-key` (600) for
   `modules/user/ai/opencode.nix`'s `apiKey =
   "{file:~/.secrets/owhug-pc1-ninfer-key}"` reference. Never commit
   either copy.
5. `/dev/nvidia*` on this host is mode `0666` (world RW), so
   `DynamicUser`'s lack of explicit `SupplementaryGroups` was never
   actually a problem — the module's `PrivateDevices = false` alone was
   sufficient.
6. `sudo nixos-rebuild switch --flake .#owhug-pc1`, then iterated on
   `services.ninfer.extraFlags` (see below) until `systemctl status
   ninfer` / `journalctl -u ninfer` showed a clean `engine ready` /
   `listening on http://0.0.0.0:8080` instead of a crash loop.

## Why vision is off

The first deploy attempt (`--max-concurrency 3`, `--vision`, native
`--max-context 262144`) failed startup with:

```
FATAL server failed during startup | minimum Engine runtime reservation
requires 12533136641 bytes in addition to 1073741824 bytes of automatic
headroom, but only 9229631488 bytes are available after weights
```

i.e. it needed ~12.5GB of runtime headroom beyond the 21.3GB weights, but
only ~8.7-9.2GB was actually available on this 32GB card (~1GB already
used by the desktop session). Dropping `--max-concurrency` to 1 (CUDA
graph capture buffers and persistent/workspace tables in
`Neroued/ninfer`'s `src/models/qwen3_5/program/planning/startup.cpp` all
scale with concurrency) only got the requirement down to ~10.2GB — still
short.

Disabling `--vision` (never actually needed for this deployment's use
case, an opencode coding-agent backend) turned out to be the dominant
lever, not `--max-context`:
`VisionContext::plan_workspace`'s `encode_peak_bytes` term — the vision
transformer's own peak workspace for encoding up to 131,072 raw patches /
32,768 merged tokens — is sized independently of `--max-context`, unlike
the text-side KV/state tables. Without `--vision`, the *full native*
262,144-token context needed only ~9.5-10.0GB, i.e. removing vision alone
recovered roughly as much headroom as the earlier concurrency cut, if not
more. The downloaded artifact still contains Vision weights; re-enabling
`--vision` later (accepting a smaller `--max-context` or
`--max-concurrency` to compensate) is a config-only change, not a
re-download.

## Why not full context

Even without vision, native 262,144 tokens needed ~9534MiB (measured:
9996672256 bytes + 1GiB headroom) against ~8.7-9.5GB actually available
(this fluctuates by ~800MiB across restarts, apparently from the desktop
session's own GPU usage) — consistently just short, by as little as
~250-500MiB in some runs. Two measurements (262144 tokens -> 9996672256
bytes required; 245760 tokens -> 9443023104 bytes required) gave a
marginal cost of ~33.8KB of runtime reservation per context token, i.e.
roughly linear. Extrapolating for a safety margin against the observed
VRAM fluctuation suggested ~204,500 tokens as the minimum safe value;
196,608 (3/4 of native, a clean number) was chosen for comfortable margin
above that estimate. This leaves ~2.06GiB free per the `capacity |` log
line at startup.

`--max-concurrency 2` was also tried at this context length once vision
was off, in case the freed VRAM allowed it: it consistently fell short by
~250-320MiB (needs ~8.3GB vs ~9.0-9.1GB available), so it's staying at 1.
Revisit only if freed VRAM increases (e.g. no desktop session running,
some other GPU consumer stops) or `--max-context` is cut further.

## Deploying a config change

1. Edit `services.ninfer.extraFlags` (or other options) in
   `./configuration.nix`.
2. `sudo nixos-rebuild switch --flake .#owhug-pc1`.
3. `systemctl status ninfer --no-pager` / `journalctl -u ninfer -n 40
   --no-pager` — look for `engine ready` and `listening on
   http://0.0.0.0:8080` vs. a `FATAL server failed during startup |
   minimum Engine runtime reservation requires N bytes ...` crash loop.
   If it's crash-looping, the log line gives the exact required/available
   byte counts needed to compute a new safe value (see "Why not full
   context" above for the method).
4. `curl http://127.0.0.1:8080/health` (unauthenticated, expect
   `{"status":"ok"}`), then an authenticated request:
   ```bash
   curl -H "Authorization: Bearer $(cat ~/.secrets/owhug-pc1-ninfer-key)" \
     http://127.0.0.1:8080/v1/models
   ```
5. If `--max-context` or vision availability changed, update the matching
   `context`/model description in `modules/user/ai/opencode.nix`'s
   `provider.owhug-pc1` entry so the client-advertised limits stay
   accurate.
6. From another LAN machine (or from opencode itself, once its
   `~/.secrets/owhug-pc1-ninfer-key` copy exists): confirm
   `http://192.168.10.26:8080/v1/models` responds, and that opencode's
   `/models` picker lists the `qwen3.8-27b` provider.

## Known gaps

- Cross-machine verification (runbook step 6 above) has not actually been
  run from a second LAN device or from opencode's own `/models` picker in
  this session — only `curl` from owhug-pc1 itself. Do this before relying
  on the provider from another machine.
- The ~800MiB VRAM-availability fluctuation between restarts was observed
  but not root-caused (plausibly the desktop session/compositor, but not
  confirmed). If it grows, `--max-context 196608` may need to shrink
  further; if it shrinks, there may be room to raise `--max-concurrency`
  back above 1.
