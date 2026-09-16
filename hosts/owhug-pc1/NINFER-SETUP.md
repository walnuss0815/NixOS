# owhug-pc1 — NInfer local LLM setup

One-time, GPU-bound steps to get `services.ninfer` (see
`./configuration.nix` and `../../modules/system/ninfer/default.nix`)
actually serving a model. None of this is expressible as a Nix
derivation: it downloads ~80GB of upstream checkpoints and runs
upstream's own Python conversion tooling against the GPU. If this file
and the module/host comments ever disagree, the `.nix` files are the
source of truth.

Target: Qwen3.8-27B, NVFP4 + Vision + the official DFlash2 speculative
drafter, ≈30GB VRAM steady state, full native 262,144-token context.

## Phase 0 — Prerequisites

1. Confirm the NVIDIA driver sees the GPU: `nvidia-smi` should list one
   RTX 5090.
2. Free disk space: you need **~100GB free, temporarily** (conversion
   inputs + output artifact), dropping to **~19GB** once the inputs
   below are deleted after conversion.
3. **RAM risk, unresolved**: the conversion step loads a 55GB BF16
   checkpoint. This box has 32GB RAM. If `tools/convert` loads weights
   fully into memory rather than streaming them from disk, this may not
   fit — check `tools/convert`'s actual memory behavior (or just try it
   and watch for OOM) before assuming this works.

## Phase 1 — Build the `ninfer` package

4. `pkgs/ninfer/default.nix` pins a commit but has a placeholder
   `hash = lib.fakeHash;` (I have no NVIDIA GPU on the machine I wrote
   it from, so couldn't compute the real one). Run:
   ```bash
   nix build .#nixosConfigurations.owhug-pc1.config.services.ninfer.package
   ```
   This will fail with a hash mismatch error reporting the *real*
   sha256. Paste that into `pkgs/ninfer/default.nix`'s `hash` field and
   rebuild.
5. **CUDA version risk, unverified**: upstream's own measurements use
   CUDA 13.1 for `sm_120a`. This derivation uses whatever `cudaPackages`
   resolves to by default in nixpkgs (was CUDA 12.9 when last checked
   from a machine without CUDA access). If the build fails on
   `sm_120a`-related errors, that's the first thing to check — look for
   a `cudaPackages_13` (or similarly named) attribute in nixpkgs and
   override `services.ninfer.package` in `./configuration.nix` to use
   it via `pkgs.callPackage ../../pkgs/ninfer { cudaPackages =
   pkgs.cudaPackages_13; }` or whatever the actual attribute turns out
   to be.
6. This is a from-scratch CUDA C++ engine; expect a real compile time
   even on the 9950X3D.

## Phase 2 — Download conversion inputs

7. Pick a scratch directory with the ~100GB free space from Phase 0,
   e.g. `/var/tmp/ninfer-convert/`.
8. Download the three inputs with the `hf` CLI (from `huggingface_hub`):
   ```bash
   hf download Qwen/Qwen3.8-27B --local-dir /var/tmp/ninfer-convert/bf16
   hf download Qwen/Qwen3.8-27B-NVFP4 --local-dir /var/tmp/ninfer-convert/nvfp4
   hf download z-lab/Qwen3.8-27B-DFlash2 --local-dir /var/tmp/ninfer-convert/dflash2
   ```

## Phase 3 — Convert

9. **Open item, unverified**: the fork's documented reproduce command
   (see NInfer's `docs/weight-conversion.md` and
   `tools/convert/recipes/`) references a precomputed
   activation-calibration JSON as a conversion input. It's not
   confirmed whether the plain official `qwen3_8_27b_nvfp4` recipe
   needs this too, or whether it's generated as part of the recipe run.
   Read `tools/convert/recipes/qwen3_8_27b_nvfp4.py` (or whatever the
   actual official recipe filename turns out to be — this wasn't
   directly inspected) before running the next command; if it wants a
   calibration file you don't have, you'll need to generate one against
   a representative text corpus first.
10. Run the conversion, from a `ninfer` checkout with a working build
    (Phase 1) and a Python 3 environment:
    ```bash
    python3 -m tools.convert \
      --model /var/tmp/ninfer-convert/bf16 \
      --source quantized=/var/tmp/ninfer-convert/nvfp4 \
      --source dflash2=/var/tmp/ninfer-convert/dflash2 \
      --recipe tools/convert/recipes/qwen3_8_27b_nvfp4.py \
      --components text,mtp,vision,dflash2 \
      --out /var/tmp/ninfer-convert/qwen3.8-27b-nvfp4-vision-dflash2.ninfer
    ```
11. If the output is a v2-format artifact, upgrade it in place (no
    re-download needed):
    ```bash
    python3 tools/upgrade_ninfer_v2_to_v3.py \
      /var/tmp/ninfer-convert/qwen3.8-27b-nvfp4-vision-dflash2.ninfer \
      /var/tmp/ninfer-convert/qwen3.8-27b-nvfp4-vision-dflash2.v3.ninfer
    ```

## Phase 4 — Install the artifact and API key

12. Move the final artifact to the path `services.ninfer.artifactPath`
    expects:
    ```bash
    sudo install -Dm644 /var/tmp/ninfer-convert/qwen3.8-27b-nvfp4-vision-dflash2*.ninfer \
      /var/lib/ninfer/models/qwen3.8-27b-nvfp4-vision-dflash2.ninfer
    ```
13. Generate the API key referenced by `services.ninfer.apiKeyFile`:
    ```bash
    sudo install -d -m 700 /var/lib/ninfer
    openssl rand -base64 32 | sudo tee /var/lib/ninfer/api-key.txt > /dev/null
    sudo chmod 600 /var/lib/ninfer/api-key.txt
    ```
    Copy this same value into an **untracked** file on every client
    machine, e.g. `~/.secrets/owhug-pc1-ninfer-key` (chmod 600), for
    opencode's `apiKey = "{file:~/.secrets/owhug-pc1-ninfer-key}"`
    reference in `modules/user/ai/opencode.nix`. Never commit either
    copy.
14. Delete the conversion inputs (`/var/tmp/ninfer-convert/{bf16,nvfp4,dflash2}`)
    to reclaim the ~80GB of temporary disk use.

## Phase 5 — Deploy and verify

15. `sudo nixos-rebuild switch --flake .#owhug-pc1`
16. `systemctl status ninfer` — check it started and actually loaded
    the artifact (`journalctl -u ninfer -f` while it comes up; model
    load will take a while).
17. `curl http://127.0.0.1:8080/health` — unauthenticated by design,
    should return `{"status":"ok"}`.
18. `curl -H 'Authorization: Bearer <the api key>' http://127.0.0.1:8080/v1/models`
19. From another LAN machine, confirm the same request works against
    owhug-pc1's LAN IP, then confirm from opencode itself (`/models`
    should list the new provider's model).

## Known gaps (not yet resolved by this runbook)

- Whether 32GB system RAM is actually sufficient to run the conversion
  tool against a 55GB BF16 checkpoint (Phase 0, step 3).
- The exact filename of the official (non-fork) `qwen3_8_27b_nvfp4`
  conversion recipe, and whether it needs a precomputed calibration
  file (Phase 3, step 9) — verify against `tools/convert/recipes/` and
  `docs/weight-conversion.md` directly rather than trusting the
  filename guessed here.
- Whether nixpkgs' default `cudaPackages` is new enough to target
  `sm_120a` (Phase 1, step 5).
- Whether `DynamicUser` needs explicit `SupplementaryGroups` (e.g.
  `"video"`) added to the `ninfer` systemd service for `/dev/nvidia*`
  access — `PrivateDevices = false` alone may not be sufficient; check
  `journalctl -u ninfer` for CUDA init failures on first start.
