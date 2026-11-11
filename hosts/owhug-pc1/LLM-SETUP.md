# owhug-pc1 — llama.cpp local LLM setup

`./llm.nix` serves an abliterated (uncensored) Qwen3.8-27B, Q8_0 GGUF,
split across both RTX 5090s with llama.cpp from nixpkgs (CUDA + NCCL).
If this file and `llm.nix` disagree, `llm.nix` is the source of truth.

- Endpoint: `http://owhug-pc1.local:8080/v1` (OpenAI-compatible), model
  alias `qwen3.8-27b`, bearer key required.
- 2 sessions (slots), each with the full native 262,144-token context.

## Running it

Start "LLM Server" from the GNOME app grid. It opens the default terminal
(Ghostty via `xdg-terminal-exec`) running `llm-server`; closing the window
stops the server and frees the GPUs. While it runs it holds a
`systemd-inhibit` sleep/idle lock, so the PC does not suspend under LAN
clients. `llm-server` can also be run by hand in any terminal.

`curl http://127.0.0.1:8080/health` returns `{"status":"ok"}` once the
model is loaded.

## One-time setup

1. Model, from
   [`huihui-ai/Huihui-Qwen3.8-27B-abliterated-GGUF`](https://huggingface.co/huihui-ai/Huihui-Qwen3.8-27B-abliterated-GGUF):
   download the Q8_0 file, then check size `29047084320` bytes and sha256
   `427b9416c2aba9d21da4e90ddac50a2bc8b6d0bfef675af3580a43aa38e000c3`:
   ```bash
   sudo install -Dm644 Huihui-Qwen3.8-27B-abliterated-Q8_0.gguf \
     /var/lib/llm/models/Huihui-Qwen3.8-27B-abliterated-Q8_0.gguf
   ```
2. API key: the value lives in the Bitwarden vault as
   `owhug-pc1-ninfer-key` (the name predates llama.cpp). opencode's nono
   session hook exports it as `OWHUG_PC1_NINFER_API_KEY`
   (`modules/user/ai/opencode.nix`). On the server:
   ```bash
   rbw get owhug-pc1-ninfer-key | sudo install -m640 -o root -g llm \
     /dev/stdin /var/lib/llm/api-key.txt
   ```
   Only the `llm` group (alexander) can read it. Never commit the key.
3. Old NInfer state can be deleted by hand: `sudo rm -rf
   /var/lib/private/ninfer` (NInfer models and key).

## Measured (llama.cpp v0.8.0, CUDA 13.4)

- `--split-mode tensor` vs `layer`: perplexity 3.7166 vs 3.7162, so no
  quality cost; q8_0 KV cache is accepted in tensor mode.
- MTP speculative decoding (`draft-mtp`, 3 draft tokens): 77.6 -> 168.9
  tok/s generation, ~74% draft acceptance.
- 2 slots x 262,144: a 254,389-token prompt returned HTTP 200, prefill
  1989 tok/s. VRAM ~29.7 of 32.6 GiB on GPU0 (desktop uses ~0.7 GiB of
  that), ~28.9 GiB on GPU1.

## Known risks

- 3 slots do not fit: startup aborts with an NCCL `ncclGroupEnd()`
  "unhandled cuda error" during warmup, almost certainly out of VRAM.
- Headroom on GPU0 is ~2.9 GiB while serving; a heavier desktop session
  (games, other CUDA apps) can push it over.
- Harmless log lines: `llama_params_fit is not implemented for
  SPLIT_MODE_TENSOR` and the CPU-sampler fallback for MTP.
- The first click on the launcher after the rebuild did nothing; later
  it worked without a config change (cause unknown). If it happens
  again, log out and in, or run `llm-server` in a terminal.
- The abliterated model's quality loss against the official one is
  unmeasured.
