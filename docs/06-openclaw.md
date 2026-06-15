# 06, OpenClaw, fully local

[OpenClaw](https://github.com/openclaw/openclaw) is an open-source autonomous personal-agent
you talk to through your existing messaging apps (Telegram, Discord, WhatsApp, Signal and
others). It takes an OpenAI-compatible LLM backend, so you can point it straight at the V100
and have your assistant run entirely on your own hardware.

This is tested end to end on the kit's V100 box: Telegram DM → gateway → local Gemma 4 → reply,
with working tool use (the agent ran `hostname` to answer where it lives). See the
[screenshot + logs](../assets/screenshots/).

> **Heads up:** OpenClaw's agent has shell access on the machine it runs on. Lock down who can
> message it (the `dmPolicy` / `groups` settings below) and treat it like giving someone a
> terminal. The config details here were checked against the official docs (docs.openclaw.ai);
> the project moves fast, so sanity-check field names if the gateway refuses to start (it
> validates strictly and rejects unknown keys).

## 1. Serve a model

Both engines expose an OpenAI-compatible endpoint. Qwen3 is the stronger pick for agent work,
Gemma 4 is faster:

```bash
./serve-qwen3.sh -c 65536 --jinja      # Qwen3 on :8001
# or: ./serve-gemma4.sh --jinja         # Gemma 4 on :8011
```

## 2. Install OpenClaw

Needs **Node 22.19+** (it hard-fails on older 22.x, `nvm install 22` if yours is older):

```bash
npm install -g openclaw@latest
openclaw onboard --install-daemon
```

The gateway process is started later with `openclaw gateway`. First run also needs
`gateway.mode` set, `openclaw config set gateway.mode local` if it complains on startup.

## 3. Make a Telegram bot

1. In Telegram, message **@BotFather** and run `/newbot`. Follow the prompts (name + username).
2. It hands back a bot token like `123456:ABC-DEF...`. Save it.
3. The token goes in the config below (or the `TELEGRAM_BOT_TOKEN` env var; config wins).
   Telegram doesn't use a `channels login` flow, you just set the token and start the gateway.

## 4. Configure

Config lives at `~/.openclaw/openclaw.json`. It's **JSON5** (comments, trailing commas and
unquoted keys are fine), not strict JSON. Minimal setup wiring Telegram to the local Qwen3
server on `:8001`:

```json5
{
  // use the local model as the agent's primary
  agents: {
    defaults: {
      model: { primary: "local/qwen3" },
    },
  },

  // Telegram channel
  channels: {
    telegram: {
      enabled: true,
      botToken: "123456:ABC-DEF...",   // from @BotFather
      dmPolicy: "pairing",             // restrict who can DM the bot
    },
  },

  // local OpenAI-compatible backend (our llama.cpp / ik_llama.cpp server)
  models: {
    mode: "merge",                     // keep hosted fallbacks available
    providers: {
      local: {
        baseUrl: "http://127.0.0.1:8001/v1",   // 8011 for Gemma
        apiKey: "sk-local",                      // ignored by the local server
        api: "openai-completions",               // /v1/chat/completions
        timeoutSeconds: 300,
        models: [
          {
            id: "qwen3",
            name: "Qwen3.6-35B-A3B (local V100)",
            reasoning: false,
            input: ["text"],
            cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
            contextWindow: 65536,    // headroom over the ~22k base context, see note below
            maxTokens: 8192,
          },
        ],
      },
    },
  },
}
```

Note `baseUrl` (camelCase, lowercase `url`) is the canonical key, `baseURL` is also accepted.
Point `baseUrl` at the right port (`:8001` Qwen, `:8011` Gemma).

> **`contextWindow` is the one that bites you, set it well above your base context, not just
> to your `-c`.** OpenClaw loads a big set of tools by default (8 plugins ≈ **22k tokens** of
> system prompt + tool defs before you've said anything). It auto-compacts when a turn passes a
> fraction of `contextWindow`, and on a *fresh* conversation there's nothing to compact, so it
> gives up and **silently drops the reply** (you message the bot and get nothing back). With a
> 22k base, a 32k window trips this immediately. Setting `contextWindow: 65536` gives enough
> headroom that normal turns don't trigger it. Your actual `serve -c` can stay at 32k as long as
> conversations stay under it; if you run long sessions, raise both. Symptom to recognise:
> gateway logs show `auto-compaction ... reason=threshold ... willRetry=false` and no delivery.

## 5. Run it

```bash
openclaw gateway
```

Then message your bot on Telegram. With `dmPolicy: pairing`, your first DM gets no visible reply
the bot returns a pairing code and you approve it once from the box running the gateway:

```bash
openclaw pairing approve telegram <CODE>
```

After that it routes through the gateway to the V100 and replies in the chat. Here it is doing
exactly that, reporting the local model and running a shell command to find the hostname:

![OpenClaw on Telegram, backed by the V100](../assets/screenshots/openclaw-telegram.png)

Gateway startup + the inbound→inference flow ([full excerpt](../assets/screenshots/openclaw-session.log)):

```
[gateway] agent model: local/gemma4 (thinking=off, fast=off)
[telegram] [default] starting provider (@claw_v100_local_bot)
[gateway] ready
[gateway/channels/telegram/inbound] Inbound message -> @claw_v100_local_bot (direct)
slot print_timing: prompt eval 23052 tokens @ 1931 tok/s | eval 201 tokens @ 52 tok/s
```

## Notes

- Same speed caveats as [Claude Code](05-claude-code.md#honest-about-speed), it's a real agent
  doing multiple LLM calls per task, so responses take a little while on a single card.
- OpenClaw is a separate long-running process from the model server. Start the server first,
  then the gateway.
- This isn't a terminal tool, so the demo is a screen capture of the Telegram chat rather than
  asciinema.

## To verify yourself (project moves fast)

- Exact `dmPolicy` / `groups` access-control semantics, check `docs.openclaw.ai/channels/telegram`.
  This matters: the agent has shell access, so gate who can talk to it.
- Whether providers go inline in `openclaw.json` (as above) or in a per-agent
  `~/.openclaw/agents/<id>/agent/models.json`, both are documented; inline is simpler.
- Field names if the gateway won't start, it validates with Zod and rejects unknown keys.
