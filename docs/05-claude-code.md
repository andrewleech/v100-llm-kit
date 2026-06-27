# 05, Claude Code, fully local

Claude Code can point straight at the local server, both engines speak the Anthropic Messages
API (`/v1/messages`), so there's no proxy or shim needed. The whole agent loop runs on your box.

**Which model:** use **Qwen3** for Claude Code, it's the stronger pick for tool use and code.
Reach for **Gemma 4** only when you want more speed on simple tasks, it's faster and has a much
gentler cold start, just less capable for multi-step agent work (see [speed](#honest-about-speed)).

## 1. Start the server (with tool calling)

The server always runs **natively on Windows** (fastest path), even if you drive Claude Code from
WSL. Claude Code needs tool calling, so start it with `--jinja`:

```powershell
# Windows, PowerShell
.\serve-qwen3.ps1 --jinja
# Windows, cmd:  serve-qwen3.bat --jinja
# Linux native:  ./serve-qwen3.sh --jinja
```

`--jinja` alone is all you need. The serve scripts auto-apply the bundled
`qwen3-template-nothink.jinja`, which both disables thinking (big latency win for agentic use) and
carries the system-message fix Claude Code relies on (see [below](#the-template-it-using-and-why)).
Don't pass a `--chat-template-file` of your own unless you mean to, it overrides that default.

## 2. Point Claude Code at it

Use the bundled launcher, it sets the `ANTHROPIC_*` env vars and runs `claude`:

```powershell
# Windows, PowerShell
.\claude-code.ps1                 # Qwen3, port 8001
.\claude-code.ps1 -Gemma          # Gemma 4, port 8011
.\claude-code.ps1 -p "what model are you?"   # extra args pass through to claude
```

```bash
# WSL or native Linux
./claude-code.sh                  # Qwen3, port 8001
./claude-code.sh --gemma          # Gemma 4, port 8011
./claude-code.sh -p "what model are you?"
```

**WSL needs mirrored networking.** The launcher reaches the native-Windows server over
`localhost`, which only works if WSL is in mirrored-networking mode. Add this to
`%USERPROFILE%\.wslconfig`, then run `wsl --shutdown` once:

```ini
[wsl2]
networkingMode=mirrored
```

### Manual setup (no launcher)

If you'd rather set it yourself, the launcher does this (Qwen shown, use port 8011 + the Gemma
name for Gemma). The model name is **not** cosmetic, Claude Code injects it into its system
prompt, so it's what the model reports when you ask what it is:

```powershell
# Windows, PowerShell
$env:ANTHROPIC_BASE_URL = "http://localhost:8001"
$env:ANTHROPIC_API_KEY  = "sk-local"          # ignored by the local server
$m = "Qwen3.6-35B-A3B"
$env:ANTHROPIC_MODEL = $m; $env:ANTHROPIC_SMALL_FAST_MODEL = $m
$env:ANTHROPIC_DEFAULT_OPUS_MODEL = $m; $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $m; $env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $m
claude
```

```bash
# WSL or native Linux
export ANTHROPIC_BASE_URL=http://localhost:8001
export ANTHROPIC_API_KEY=sk-local             # ignored by the local server
m=Qwen3.6-35B-A3B
export ANTHROPIC_MODEL=$m ANTHROPIC_SMALL_FAST_MODEL=$m
export ANTHROPIC_DEFAULT_OPUS_MODEL=$m ANTHROPIC_DEFAULT_SONNET_MODEL=$m ANTHROPIC_DEFAULT_HAIKU_MODEL=$m
claude
```

## Check you're really local

Ask `claude -p "what model are you?"`. With the real model name set it reports
"Qwen3.6-35B-A3B, by Alibaba's Tongyi Lab", confirming you're on the card and not calling out to
Anthropic. Watch out: if you set `ANTHROPIC_MODEL=local` (or some placeholder), Claude Code's
system prompt gives the model no real identity to report, so it falls back to the Claude persona
and claims to be Claude. That's not a wrong endpoint, it's just the system prompt. Set the real
name and it reports honestly.

<!-- DEMO: asciinema/gif, "what model are you" -->
<!-- DEMO: asciinema/gif, quick query on a project -->

## The template it's using, and why

Out of the box with `--jinja` you'd hit `500: System message must be at the beginning`. The
stock Qwen3 chat template raises if a system message isn't first, and Claude Code sends extra
system blocks. The bundled `qwen3-template-nothink.jinja` fixes that (it renders a non-leading
system message as a normal system turn) **and** forces thinking off. The serve scripts apply it
automatically under `--jinja`, so there's nothing extra to pass, this is handled for you.

If you specifically want thinking **on** (slower, see below) while keeping the system-message fix,
use the thinking variant explicitly:

```bash
./serve-qwen3.sh --jinja --chat-template-file qwen3-template-think.jinja
# Windows: .\serve-qwen3.ps1 --jinja --chat-template-file qwen3-template-think.jinja
```

## Honest about speed

Claude Code sends a big (~24k token) system prompt. The server caches it after the first turn
(`-cram` RAM prompt cache), so you pay the prompt-processing cost once as a cold start, then
every turn after restores it from cache and only processes your new message. Measured per turn:

| | Cold first turn | Warm turns (cached) |
|---|---|---|
| Gemma 4 | ~15s | ~2.5s |
| Qwen3 | ~2.5 min | ~4.5s |

So it's slow once, then snappy, not slow every turn. The cold start is the gap: Gemma processes
the 24k prompt in ~12s (pure GPU), Qwen takes ~2.5 min because MoE expert offload makes
long-prompt processing ~11x slower. Qwen is still the better agent once warm; if the long cold
start bothers you on quick, simple tasks, that's when Gemma earns its place. Add a longer reply
and the warm turn grows by the generation time on top.

Two things that wreck this if you get them wrong:
- **Thinking on.** Both models think by default, which adds big latency (Qwen ruminated 2.5 min
  on a trivial question once). The no-think template is the default for agentic work, don't
  override it back to a thinking template unless you mean to.
- **Cache busting.** The cache keys on the prompt prefix. Changing `-c`, the model, or the
  template restarts cold. A stable setup stays warm across `claude` invocations.

Keep `-c` sized to a real session (system prompt + a few files is already 20-40k tokens),
`-c 65536` is a sensible floor.

## Recording the demo

The kit has a recorder at `scripts/demo/record-claude-code.sh` that drives an interactive
session in tmux and captures it with asciinema, then `cast-to-gif.sh` converts it. See
`scripts/demo/scenarios/` for the prompts.
