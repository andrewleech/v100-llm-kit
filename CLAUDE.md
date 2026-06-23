# v100-llm-kit

Setup pack for running local LLMs on a **Tesla V100-SXM2-16GB** (Volta, **SM_70**, fp16-only,
16 GB HBM2). Prebuilt binaries, serve scripts, and step-by-step docs for Windows and Linux,
plus wiring for Claude Code and OpenClaw. Aimed at buyers of these cards.

## Layout

- `docs/` — numbered setup guides: `01-hardware` (MCDM driver), `02-linux-setup`,
  `03-windows-setup`, `04-models`, `05-claude-code`, `06-openclaw`, `07-dual-nvlink`, `benchmarks`.
- `scripts/linux/` + `scripts/windows/` — serve + download scripts, and chat templates.
- `scripts/demo/` — asciinema recorders and the streaming chat client for the README gifs.
- `assets/` — `gifs/` + `casts/` (demos), `screenshots/` (OpenClaw), `photos/` (GPU, TODO).
- `releases/` — notes on the prebuilt binary release ZIPs.
- `blog-post-draft.md` — draft post for notes.alelec.net (not auto-published).

## Key facts (don't re-derive these)

- **Two engines, two model shapes.** Gemma 4 26B-A4B (QAT Q4_0) runs on **upstream llama.cpp**
  — pure GPU, needs sliding-window-attention KV compression. Qwen3.6 35B-A3B (IQ4_XS) runs on
  **ik_llama.cpp** — MoE expert offload to CPU RAM. Don't swap these; ik can't do Gemma's SWA-KV.
- **Binaries are SM_70 only.** CUDA 12.x required (CUDA 13.3 dropped Volta). Windows: CUDA 12.8.
- **Windows driver: R570–R580 window, use R570 573.96.** CUDA 12.8 binaries need driver >= R570
  (570.65) or kernels won't load (`device kernel image is invalid`, so R535/539.72 is too old);
  Volta is supported only through R580 (R595/CUDA 13.3 drops it). Use the R570 data-center driver
  573.96. See `docs/01-hardware.md`.
- **Dual-card power: use a strong PSU.** The dual-V100 box's spontaneous reboots under sustained
  dual-card load (a `0x133 DPC_WATCHDOG_VIOLATION` at low temp, well under the power cap) were an
  insufficient power supply — the current transient when both cards ramp together, not the driver
  (reproduced across R570 and R580) and not thermal. A single card is fine on any sensible supply;
  two need a good unit with headroom and solid transient response. See `docs/01-hardware.md`.
- **Both models think by default; thinking is disabled** for agentic use via the bundled
  `*-template-nothink.jinja`, which the serve scripts auto-apply under `--jinja` (`THINK=1` opts
  back in).
- **Windows native TG is faster than WSL2** (~21% Gemma, ~43% Qwen) — see `docs/benchmarks.md`.
- **Claude Code / OpenClaw cold-start:** the ~24k-token system prompt is processed once then
  cached (`-cram`); warm turns are fast. Gemma's cold start (~15s) beats Qwen's (~2.5min).
- **Dual V100 + NVLink is for multi-agent/concurrency, not single-stream.** Use upstream llama.cpp
  built with `-DGGML_CUDA_NCCL=ON` (against nccl-windows, sm_70) + `-sm tensor` + env
  `GGML_CUDA_ALLREDUCE=nccl` + `--parallel N` (see `serve-dual-nccl.bat`, `docs/07-dual-nvlink.md`).
  NCCL-over-NVLink gives ~7-9% more aggregate throughput (almost all of it prompt processing,
  decode is a wash) vs the Windows-default `internal` all-reduce under load; an earlier ~40-50%
  figure was a thermal-throttling artifact, see `docs/benchmarks.md`. Single card is faster for a
  single stream of a model that fits 16 GB.

## Conventions

- Serve/download scripts resolve paths relative to themselves; override with `BIN_DIR` / `MODEL`
  / `MODEL_DIR` env vars. Windows `.bat` files must keep CRLF line endings.
- Demo gifs play at **real speed (no speed-up)** — only idle is trimmed (`scripts/demo/cast-to-gif.sh`).
  This is deliberate: speeding them up would misrepresent the hardware.
- Model weights and built binaries are gitignored (`models/`, `*.gguf`, `bin/`, `*.exe/.dll/.so`).
