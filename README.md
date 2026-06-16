# V100 LLM Kit

Run capable LLMs fully locally on a Tesla V100-SXM2-16GB. Prebuilt binaries, serve scripts,
and step-by-step setup for both Windows and Linux, plus how to point Claude Code and OpenClaw
at the box so your coding agent and your assistant run entirely on your own hardware.

The V100 is a 2017 datacentre card you can pick up cheap now, 16 GB of HBM2 at ~900 GB/s. That
memory bandwidth is what matters for token generation, and it's still pretty good. The catch is
it's Volta (compute 7.0, fp16 only, no bf16 or int8 tensor cores), so a fair bit of modern
quant advice doesn't apply. This kit is tuned around what the card can actually do.

> **Hardware scope:** binaries here are built for **SM_70 (Volta / V100) only**. They won't run
> on other GPUs without a rebuild. If you bought a card from me, these are the ones for you.

## What you get

Two inference engines, because two model shapes need different things:

| Model | Engine | Why | Fits |
|---|---|---|---|
| **Gemma 4 26B-A4B** (QAT Q4_0) | upstream llama.cpp | needs sliding-window-attention KV compression | entirely in 16 GB, pure GPU |
| **Qwen3.6 35B-A3B** (IQ4_XS) | ik_llama.cpp | MoE expert offload + faster CPU GEMM | GPU + a bit of CPU RAM |

Gemma 4 is the easy one, it's all on the GPU so it's fast and simple. Qwen3 is the bigger,
stronger model but it offloads some experts to CPU RAM, so it's a touch slower and wants a
decent CPU. Pick whichever suits, the kit serves both.

## Quick start

1. **Driver:** get the card into MCDM mode (see [docs/01-hardware.md](docs/01-hardware.md)).
   On Linux native you can skip this.
2. **Grab the binaries** for your OS from [Releases](../../releases), extract somewhere.
3. **Pull a model:** `scripts/<os>/download-models.*` (needs a free Hugging Face account).
4. **Serve it:** `scripts/<os>/serve-gemma4.*` or `serve-qwen3.*`.
5. **Use it:** OpenAI-compatible API at `http://localhost:8011` (Gemma) or `:8001` (Qwen).
   Wire up [Claude Code](docs/05-claude-code.md) or [OpenClaw](docs/06-openclaw.md).

## Docs

1. [Hardware & driver setup](docs/01-hardware.md)
2. [Linux / WSL2 setup](docs/02-linux-setup.md)
3. [Windows native setup](docs/03-windows-setup.md)
4. [Models: which, how to pull, sizing](docs/04-models.md)
5. [Claude Code, fully local](docs/05-claude-code.md)
6. [OpenClaw, fully local](docs/06-openclaw.md)
7. [Dual V100 + NVLink (multi-agent serving)](docs/07-dual-nvlink.md)

Plus [Benchmarks](docs/benchmarks.md) for the numbers.

## See it running

Ask either model what it is and it tells you the truth, because it's running on your card, not
Anthropic's:

![Gemma 4 reporting its identity](assets/gifs/chat-identity-gemma.gif)
![Qwen3 reporting its identity](assets/gifs/chat-identity-qwen.gif)

Claude Code pointed at the local server: two quick chat answers (from the project's CLAUDE.md,
~1-4s each) then a file read showing real code. Note the model name in the status bar, the
whole agent loop runs on the V100:

![Claude Code on the local model](assets/gifs/claude-project-tour.gif)

Same session on the dual-V100 card running the bigger Qwen3.6 35B fully resident across both GPUs.
On a single card that model offloads experts to CPU and the cold start is ~2.5 min; held resident
on two cards it's ~13s, with warm turns about a second ([docs/07](docs/07-dual-nvlink.md)):

![Claude Code on dual-card Qwen3 35B](assets/gifs/claude-qwen-dual.gif)

These play at real speed (no speed-up), only dead air between turns is trimmed.

And OpenClaw driving the same card through Telegram, it reports the local model, and even runs
a shell command (`hostname`) to answer where it's running:

![OpenClaw on Telegram, backed by the V100](assets/screenshots/openclaw-telegram.png)

The gateway startup and the inbound-message → local-inference flow, from the logs:

```
[gateway] agent model: local/gemma4 (thinking=off, fast=off)
[telegram] [default] starting provider (@claw_v100_local_bot)
[gateway] ready
[gateway/channels/telegram/inbound] Inbound message -> @claw_v100_local_bot (direct)
# Gemma 4 on the V100 handles the turn:
slot print_timing: prompt eval 23052 tokens @ 1931 tok/s | eval 201 tokens @ 52 tok/s
```

## How fast is it, honestly

Token generation lands around 28-37 tok/s on Qwen3 and ~47-57 tok/s on Gemma 4 depending on
context and OS. That's comfortably usable for chat and for Claude Code, slower than a frontier
API but it's running on a card in your cupboard with nothing leaving the machine. Windows native
is measurably quicker than WSL2 for generation (the virtualisation layer taxes the
memory-bound decode path), numbers in [docs/benchmarks.md](docs/benchmarks.md).

One thing worth knowing for Claude Code: it sends a big (~24k token) system prompt, and the
server caches it after the first turn (RAM prompt cache, `-cram`). So you pay the prompt
processing once as a cold start, then every turn after restores it from cache and only
processes your new message. Measured per turn:

| | Cold first turn | Warm turns (cached) |
|---|---|---|
| Gemma 4 | ~15s | ~2.5s |
| Qwen3 | ~2.5 min | ~4.5s |

Warm turns are quick on both. The difference is the cold start: Gemma processes that 24k
prompt in ~12s (pure GPU), Qwen takes ~2.5 min because its MoE expert-offload makes
long-prompt processing much slower. So Gemma's the nicer Claude Code experience, mostly
because of the gentle cold start. Add a longer reply and the warm turn grows by the generation
time on top.

That Qwen cold start is a single-card limitation, not the model's. On the dual-V100 card it runs
fully resident across both GPUs with no CPU offload, which drops the cold start to ~13s, see
[docs/07-dual-nvlink.md](docs/07-dual-nvlink.md).

## License

MIT. The bundled engines (llama.cpp, ik_llama.cpp) keep their own upstream licenses.
