# 04 — Models

Two models, two engines. Pull whichever you want (or both) with the download scripts.

| Model | Repo | File | Size | Engine |
|---|---|---|---|---|
| Gemma 4 26B-A4B QAT | `google/gemma-4-26B-A4B-it-qat-q4_0-gguf` | `gemma-4-26B_q4_0-it.gguf` | ~13.4 GB | upstream llama.cpp |
| Qwen3.6 35B-A3B | `byteshape/Qwen3.6-35B-A3B-MTP-GGUF` | `Qwen3.6-35B-A3B-IQ4_XS-4.19bpw.gguf` | ~18.6 GB | ik_llama.cpp |

## Pulling them

Needs a free [Hugging Face account](https://huggingface.co/join) and a
[token](https://huggingface.co/settings/tokens), plus the `hf` CLI:

```bash
pip install -U "huggingface_hub[hf_transfer]"
hf auth login        # paste your token
```

Then:

```bash
# Linux / WSL2
./download-models.sh            # both
./download-models.sh gemma      # just Gemma 4
./download-models.sh qwen       # just Qwen3

# Windows
download-models.bat
```

## Which to use

**Gemma 4** — fits entirely in 16 GB VRAM, pure GPU, fast (~47-57 tok/s TG). The QAT
(quantisation-aware training) build holds up better at 4-bit than a normal post-training quant.
Best for chat and quick tasks, and when you want simple and fast.

**Qwen3.6** — bigger, stronger MoE model (~3B active params). Offloads some experts to CPU RAM,
so it's a bit slower (~26-38 tok/s TG) and wants a decent CPU, but it's the better model for
coding and multi-step agent work. The `-MTP-` repo includes the multi-token-prediction draft
head for speculative decoding.

## Sizing context

Pick `-c` for what you actually use. A bigger context reserves more KV cache up front:

- **Gemma 4:** KV stays small (SWA compression), ~1.3 GiB at 32k, ~5 GiB at 128k. All fits in
  16 GB, so context is cheap-ish — push it up if you need long documents.
- **Qwen3:** reserving a big context forces more experts off the GPU onto CPU, which slows every
  turn even when the context sits empty. So keep it tight (32-64k) for chat, bump it only when
  you genuinely paste big documents in.

## Storage rule (matters)

GGUF files must live on the **native filesystem of the OS running llama.cpp**. Never share model
files across the Windows/WSL boundary either way:

- WSL2 → keep on ext4 (the kit's `models/` dir), never `/mnt/c` or `/mnt/d`. NTFS-over-9p is
  3-5x slower for mmap and breaks `--mlock`.
- Windows native → keep on a Windows NTFS drive, never a `\\wsl$\...` path.
