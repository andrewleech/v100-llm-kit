# v100-llm-kit

Setup pack for running local LLMs on a **Tesla V100-SXM2-16GB** (Volta, **SM_70**, fp16-only,
16 GB HBM2). Prebuilt binaries, serve scripts, and step-by-step docs for Windows and Linux,
plus wiring for Claude Code and OpenClaw. Aimed at buyers of these cards.

## Layout

- `docs/` — numbered setup guides: `01-hardware` (MCDM driver), `02-linux-setup`,
  `03-windows-setup`, `04-models`, `05-claude-code`, `06-openclaw`, `benchmarks`.
- `scripts/linux/` + `scripts/windows/` — serve + download scripts, and chat templates.
- `scripts/demo/` — asciinema recorders and the streaming chat client for the README gifs.
- `assets/` — `gifs/` + `casts/` (demos), `screenshots/` (OpenClaw), `photos/` (GPU, TODO).
- `releases/` — notes on the prebuilt binary release ZIPs.
- `blog-post-draft.md` — draft post for notes.alelec.net (not auto-published).

## Key facts (don't re-derive these)

- **Two engines, two model shapes.** Gemma 4 26B-A4B (QAT Q4_0) runs on **upstream llama.cpp**
  — pure GPU, needs sliding-window-attention KV compression. Qwen3.6 35B-A3B (IQ4_XS) runs on
  **ik_llama.cpp** — MoE expert offload to CPU RAM. Don't swap these; ik can't do Gemma's SWA-KV.
- **Binaries are SM_70 only.** CUDA 12.x required (13.0+ dropped Volta). Windows: CUDA 12.8.
- **Both models think by default; thinking is disabled** for agentic use via the bundled
  `*-template-nothink.jinja`, which the serve scripts auto-apply under `--jinja` (`THINK=1` opts
  back in).
- **Windows native TG is faster than WSL2** (~21% Gemma, ~43% Qwen) — see `docs/benchmarks.md`.
- **Claude Code / OpenClaw cold-start:** the ~24k-token system prompt is processed once then
  cached (`-cram`); warm turns are fast. Gemma's cold start (~15s) beats Qwen's (~2.5min).

## Conventions

- Serve/download scripts resolve paths relative to themselves; override with `BIN_DIR` / `MODEL`
  / `MODEL_DIR` env vars. Windows `.bat` files must keep CRLF line endings.
- Demo gifs play at **real speed (no speed-up)** — only idle is trimmed (`scripts/demo/cast-to-gif.sh`).
  This is deliberate: speeding them up would misrepresent the hardware.
- Model weights and built binaries are gitignored (`models/`, `*.gguf`, `bin/`, `*.exe/.dll/.so`).
