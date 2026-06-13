# 05 — Claude Code, fully local

Claude Code can point straight at the local server — both engines speak the Anthropic Messages
API (`/v1/messages`), so there's no proxy or shim needed. The whole agent loop runs on your box.

## Serve with tool calling on

Claude Code needs tool calling, so start the server with `--jinja`:

```bash
# Linux / WSL2
./serve-qwen3.sh -c 65536 --jinja
# Windows: set CTX=65536 & serve-qwen3.bat --jinja
```

Qwen3 is the better pick for Claude Code (stronger at tool use and code). Gemma 4 works too and
is faster, just less capable for multi-step agent work.

## Point Claude Code at it

```bash
export ANTHROPIC_BASE_URL=http://localhost:8001     # 8011 for Gemma
export ANTHROPIC_API_KEY=sk-local                   # ignored by the local server
# Set the model name to the REAL model, not "local" — Claude Code injects this into its
# system prompt, so this is what the model reports when you ask what it is.
export ANTHROPIC_MODEL="Qwen3.6-35B-A3B" ANTHROPIC_SMALL_FAST_MODEL="Qwen3.6-35B-A3B"
export ANTHROPIC_DEFAULT_OPUS_MODEL="Qwen3.6-35B-A3B" ANTHROPIC_DEFAULT_SONNET_MODEL="Qwen3.6-35B-A3B" ANTHROPIC_DEFAULT_HAIKU_MODEL="Qwen3.6-35B-A3B"

claude -p "what model are you?"     # headless one-shot
claude                               # interactive
```

Asking "what model are you" is a good check — with the real model name set it reports
"Qwen3.6-35B-A3B, by Alibaba's Tongyi Lab", confirming you're on the card and not calling out
to Anthropic. Watch out: if you set `ANTHROPIC_MODEL=local` (or leave it as some placeholder),
Claude Code's system prompt gives the model no real identity to report, so it falls back to
the Claude persona and claims to be Claude. That's not a wrong endpoint — it's just the system
prompt. Set the real name and it reports honestly.

<!-- DEMO: asciinema/gif — "what model are you" -->
<!-- DEMO: asciinema/gif — quick query on a project -->

## The Qwen3 template patch

Out of the box with `--jinja` you may hit `500: System message must be at the beginning`. The
Qwen3 chat template raises if a system message isn't first, and Claude Code sends extra system
blocks. The fix is a one-line template patch (swap the `raise_exception(...)` for rendering the
content as a normal system turn). The patched template ships in the kit as
`qwen3-template-patched.jinja`:

```bash
./serve-qwen3.sh -c 65536 --jinja --chat-template-file qwen3-template-patched.jinja
```

## Honest about speed

Claude Code sends a big (~24k token) system prompt. The server caches it after the first turn
(`-cram` RAM prompt cache), so you pay the prompt-processing cost once as a cold start, then
every turn after restores it from cache and only processes your new message. Measured per turn:

| | Cold first turn | Warm turns (cached) |
|---|---|---|
| Gemma 4 | ~15s | ~2.5s |
| Qwen3 | ~2.5 min | ~4.5s |

So it's slow once, then snappy — not slow every turn. The cold start is the deciding factor:
Gemma processes the 24k prompt in ~12s (pure GPU), Qwen takes ~2.5 min because MoE expert
offload makes long-prompt processing ~11x slower. **For Claude Code, Gemma 4 is the better
pick** mostly for that gentle cold start; warm turns are fine on both. Add a longer reply and
the warm turn grows by the generation time on top.

Two things that wreck this if you get them wrong:
- **Thinking on.** Both models think by default, which adds big latency (Qwen ruminated 2.5 min
  on a trivial question once). Use the no-think template variants for agentic work — `serve`
  defaults to them.
- **Cache busting.** The cache keys on the prompt prefix. Changing `-c`, the model, or the
  template restarts cold. A stable setup stays warm across `claude` invocations.

Keep `-c` sized to a real session (system prompt + a few files is already 20-40k tokens),
`-c 65536` is a sensible floor.

## Recording the demo

The kit has a recorder at `scripts/demo/record-claude-code.sh` that drives an interactive
session in tmux and captures it with asciinema, then `cast-to-gif.sh` converts it. See
`scripts/demo/scenarios/` for the prompts.
