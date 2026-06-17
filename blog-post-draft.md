---
title: "A Tesla V100 in the Cupboard: Fully Local Claude Code and OpenClaw"
date: 2026-06-13T10:30:00+10:00
tags: [ai, claude, hardware, llm]
---

The Tesla V100 is a 2017 datacentre card that's gone pretty cheap on the second-hand market,
and it turns out it's still a genuinely good bang-for-buck way to run LLMs locally in 2026. 16
GB of HBM2 at around 900 GB/s, and that memory bandwidth is the thing that actually matters for
token generation. I've been assembling a few of these into machines and putting together a
setup pack so anyone buying one can get going without fighting the toolchain, so this post is
partly the story of getting there and partly a pointer to the kit.

**tldr:** Gemma 4 26B and Qwen3.6 35B both run nicely on a single V100, ~28-57 tok/s depending
on the model, fast enough to drive Claude Code and OpenClaw with nothing leaving the machine.
Prebuilt binaries and scripts for Windows and Linux are at
[github.com/andrewleech/v100-llm-kit](https://github.com/andrewleech/v100-llm-kit).

<!-- PHOTO: the V100 SXM2 card in the machine -->

## Why a V100 in 2026

The honest answer is price. Frontier API models are better, no argument, but a V100 you own
runs forever for the cost of power and never sends a token off the box. For coding agents
especially that's worth a fair bit, the whole repo stays local. The card's a bit awkward
though, it's Volta (compute 7.0), which means fp16 only, no bf16 and no int8 tensor cores. A
lot of the modern quant advice floating around leans on those, so you can't just copy a recipe
across, you have to build for what the card actually has.

## The MCDM gotcha

This one caught me out for a while. The V100 SXM2 is a headless compute card, no display
outputs, so the Windows datacentre driver defaults it to TCC mode. TCC is great for raw CUDA
but WSL2's GPU passthrough can't use it, you just get `Failed to initialize NVML` inside WSL
and nothing works.

The fix is MCDM mode (Microsoft Compute Driver Model), which is the GPU-PV compatible one. WDDM
isn't available on this card because there's no display engine, so MCDM is the only route that
lets WSL2 see the GPU. Once it's flipped over (registry + reboot, done once) the card shows up
fine inside WSL. If you're running native Linux you can ignore all of this.

## Two engines, because two model shapes

I ended up running two different builds of llama.cpp, which felt like overkill at first but
there's a real reason.

**Gemma 4 26B-A4B** is the easy one. The Google QAT (quantisation-aware training) Q4_0 build
fits entirely in 16 GB VRAM, 13.43 GiB loaded with about 1.3 GiB of KV at 32k context, so it's
pure GPU with no CPU offload at all. The catch is it needs sliding-window-attention KV
compression to keep that KV small, and upstream llama.cpp implements that. The ik_llama.cpp
fork doesn't, so on ik the same model tries to allocate 56 GB of KV at 4k tokens and just OOMs.
So Gemma 4 runs on upstream.

**Qwen3.6 35B-A3B** is the bigger, stronger model. It's a mixture-of-experts with ~3B active
parameters per token, and at 4-bit the weights don't quite fit, so it offloads some experts to
CPU RAM. For that I use ik_llama.cpp, which has the MoE expert-offload handling and faster CPU
GEMM kernels. It's a touch slower than Gemma 4 because some compute happens on the CPU, but it's
a more capable model and still very usable.

So the kit ships both. Gemma 4 if you want fast and simple, Qwen3 if you want the stronger model
and don't mind a few tok/s less.

## Windows native vs WSL2

I built and benchmarked both, same model, same commit, same flags, on the same machine. Prompt
processing is basically identical between the two. Token generation though is meaningfully faster
on Windows native, and the gap is bigger for Qwen3 than Gemma 4.

| Model | Test | Windows native | WSL2 |
|---|---|---|---|
| Gemma 4 | TG | 56.8 tok/s | 47.0 tok/s |
| Qwen3 | TG | 37.7 tok/s | 26.3 tok/s |

That's ~21% for Gemma 4 and ~43% for Qwen3. The pattern makes sense once you think about it,
the WSL2 GPU-PV layer adds latency on the memory-bound decode path, and Qwen3 pays it more
because MoE expert offload means lots of GPU-to-CPU round trips, each one wearing the
virtualisation tax. Gemma 4 is pure GPU so there's far less back and forth. If you want the most
speed, run native, the kit covers both.

## Proving it's actually local

Easiest way to show nothing's leaving the box, ask the model what it is. In a plain chat the
local model tells you the truth, Gemma says it's Gemma by Google, Qwen says it's Qwen by
Alibaba. No cloud model would admit to being a competitor's.

![Gemma reporting it's Gemma by Google](_assets/v100-kit/chat-identity-gemma.gif)
![Qwen reporting it's Qwen by Alibaba](_assets/v100-kit/chat-identity-qwen.gif)

One gotcha I hit, through Claude Code specifically the answer isn't reliable. Claude Code sends
a system prompt telling the model "you are Claude Code", and an obedient local model plays
along and says it's Claude. That threw me at first, it looks like it's phoning home when it
isn't. The fix is just to ask in a plain chat, or trust the model name shown right there in the
Claude Code status bar.

## Claude Code, fully local

Point Claude Code at the local server and it just works, the server speaks the Anthropic
Messages API so there's no shim needed. Here it is on a small project: a couple of quick chat
answers (straight from the project's CLAUDE.md, so no tool call needed) then a file read showing
real code, model name in the status bar, the whole agent loop running on the V100:

![Claude Code doing real work on the local model](_assets/v100-kit/claude-project-tour.gif)

That's real speed, no speed-up, only the dead air trimmed. The thing that surprised me here was
how much the prompt cache matters. Claude Code sends a big system prompt (~24k tokens) and the
server caches it after the first turn, so the cost is a one-off cold start, then every turn after
restores from cache and only processes your new message. Measured it: a cold first turn is ~15s
on Gemma and a brutal ~2.5 min on Qwen, but warm turns are ~2.5s and ~4.5s respectively. So it's
slow once then snappy, not slow every turn like I first assumed.

The cold-start gap is the whole story for picking a model. Gemma processes that 24k prompt in
~12s because it's pure-GPU, Qwen takes ~2.5 min because its MoE expert-offload makes long-prompt
processing about 11x slower. So Gemma's the nicer Claude Code experience, basically because you
wait 15s once instead of a couple of minutes. Both are thinking models by default which piles on
latency, so for agentic use I run them with thinking off (the kit ships no-think template
variants). Still slower than a frontier API, but genuinely usable and nothing leaves the machine.

## OpenClaw, fully local

OpenClaw's the wildly popular personal-agent thing that runs through your messaging apps. It
takes an OpenAI-compatible backend, so pointing it at the V100 is just a baseURL and any
non-empty API key. I wired it to Telegram and the local Gemma 4, and it just works, it reports
the local model and will even run a shell command to answer a question about the box:

![OpenClaw on Telegram, backed by the V100](_assets/v100-kit/openclaw-telegram.png)

Under the hood it's the same story as Claude Code, the gateway routes the Telegram message to
the V100 and streams back the reply:

```
[gateway] agent model: local/gemma4 (thinking=off, fast=off)
[telegram] [default] starting provider (@claw_v100_local_bot)
[gateway] ready
[gateway/channels/telegram/inbound] Inbound message -> @claw_v100_local_bot (direct)
# Gemma 4 on the V100 handles the turn:
slot print_timing: prompt eval 23052 tokens @ 1931 tok/s | eval 201 tokens @ 52 tok/s
```

A couple of gotchas worth knowing if you try this. OpenClaw wants Node 22.19+, and it loads a
big pile of tools by default (~22k tokens of context before you've said anything), so you have
to tell it the model's context window is comfortably bigger than that or it panic-compacts a
fresh conversation and silently drops the reply. Once that's sorted it's solid. Full setup in
the kit docs.

## Dual V100 with NVLink, for multi-agent

<!-- PHOTO: the dual-V100 NVLink card -->

I built a PCIe card that mounts two V100s with an NVLink bridge between them. It bifurcates the
slot x8/x8 and the bridge is a 2-link one, about 51 GB/s. The point of it was multi-agent serving,
lots of concurrent requests at once, with NVLink doing the heavy lifting between the cards.

First thing I got wrong: I assumed GPU-to-GPU P2P was blocked on Windows. It isn't. A direct
`cudaMemcpyPeer` test does 33 GB/s across the bridge in TCC mode, well above the x8 PCIe link, so
NVLink works fine on Windows, you just have to actually use it.

A couple of things that matter. For a single request of a model that fits on one card (Gemma 4),
one card is fastest, splitting it across two just adds sync overhead and comes out slower. So for
single-user work on a model that fits, the second card does nothing, don't bother.

That fits-one-card bit is the catch though. Qwen3 35B doesn't fit, and that's where the second
card earns its keep even single threaded. On one card it has to offload experts to CPU RAM, which
is exactly what makes its Claude Code cold start so brutal, about 2.5 min to chew through that 24k
system prompt. Put it across both cards with layer split and the whole model sits in VRAM, no CPU
offload at all, and that same cold start drops to ~13s. Here's the project tour from earlier, same
prompts, running Qwen3 35B on the dual card:

![Claude Code on dual-card Qwen3 35B, fully resident](_assets/v100-kit/claude-qwen-dual.gif)

Warm turns after that are about a second. So the second card doesn't just buy you concurrency, it
makes the bigger, stronger model genuinely pleasant single threaded, which the single card never
managed because of all that CPU offload. Real speed, no speed-up, same as the other gifs.

The other win is concurrency. Run the model tensor-parallel (`-sm tensor`) across both cards and throw a
pile of requests at it and the second card earns its keep. The tricky bit is the all-reduce
between the cards every layer, which is the thing NVLink is actually for. llama.cpp can use NCCL
for that, but it turns out it defaults to its own internal all-reduce on Windows and only picks
NCCL by default on Linux, so on Windows NCCL is opt-in via `GGML_CUDA_ALLREDUCE=nccl`.

There's no NCCL for Windows from NVIDIA though, so I built one (the SystemPanic/nccl-windows port,
compiled for sm_70) and rebuilt llama.cpp against it. With that in place NCCL runs the all-reduce
straight over NVLink P2P, the log confirms it with `via P2P/direct pointer`. The numbers are more
modest than I first thought though. On Qwen3 35B and Gemma at 16-32 concurrent, NCCL over NVLink is
about 7-9% more aggregate throughput than the Windows default, and it's basically all prompt
processing (~30% faster PP), decode comes out a wash. The NVLink bridge itself is worth a touch more
once you isolate it, +17-21% aggregate, and tellingly NCCL with P2P disabled (all-reduce through host
RAM) is actually slower than the built-in Windows path. So NVLink is genuinely doing the work, NCCL
without it isn't worth having, it's just that for mixed prefill+decode load the all-reduce isn't the
whole story.

Worth being honest about how I got that number wrong at first. My early benchmarks had one GPU
thermally throttling, which dragged the baseline down and made NCCL look like a 40-50% win. Once the
fans were sorted and I re-ran it back to back at 60-odd degrees, the real gap was about a third of
that. The throttling fooled me, the cool numbers are the ones to trust. (There's a prefill-heavy
real-server test where it looked more like +22%, but that one predates the fan fix too, so I'd take
it with salt until I re-run it.)

So for a Windows box doing multi-agent: nccl-windows + llama.cpp built with NCCL, `-sm tensor`,
`GGML_CUDA_ALLREDUCE=nccl`, `--parallel N`. All native Windows, no Linux required, build steps are
in the kit ([docs/07](https://github.com/andrewleech/v100-llm-kit/blob/main/docs/07-dual-nvlink.md)).

vLLM would be the stronger throughput engine and I had a real go at it. It builds on Windows for
sm_70, which I'm pretty sure is a first, but it won't actually run, torch's gloo can't bring up its
comms backend on Windows. Getting past that needs a torch rebuild from source, and even then
vLLM's tensor-parallel wants NCCL anyway, so llama.cpp + NCCL gets to the same place with a lot
less pain.

One aside that surprised me: flipping the cards from MCDM to TCC looked like it roughly doubled
single-card decode. I haven't pinned it down with a clean A/B yet (build and KV settings differ
too) but if it holds it's a bigger lever than any of the multi-GPU stuff. On the list. Numbers for
all of this are in the
[kit benchmarks](https://github.com/andrewleech/v100-llm-kit/blob/main/docs/benchmarks.md).

## The kit

Everything's at [github.com/andrewleech/v100-llm-kit](https://github.com/andrewleech/v100-llm-kit):
prebuilt SM_70 binaries for Windows and Linux, serve scripts, model-download helpers, and
step-by-step setup for the driver, the models, Claude Code and OpenClaw. If you grabbed a card
from me, that's where to start.
