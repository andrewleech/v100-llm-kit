#!/usr/bin/env python3
"""Minimal streaming chat against the local OpenAI-compatible server, for demo recordings.

Prints a shell-style prompt line, then streams the model's reply token-by-token at real
speed (no speed-up). Shows the model's true identity without any Claude Code persona in the
way, so a local Gemma/Qwen reports itself honestly — a clean "it's running on the box" proof.

Usage: chat-once.py "<question>"   (env: BASE_URL, default http://localhost:8011/v1)
"""
import json, os, sys, urllib.request

BASE = os.environ.get("BASE_URL", "http://localhost:8011/v1").rstrip("/")
PROMPT = sys.argv[1] if len(sys.argv) > 1 else "What model are you and who made you?"

# Shell-style banner so the recording reads like a terminal session.
sys.stdout.write(f"\033[01;32m$\033[0m \033[01;36mask\033[0m \"{PROMPT}\"\n\n")
sys.stdout.flush()

body = json.dumps({
    "model": "local",
    "messages": [{"role": "user", "content": PROMPT}],
    "max_tokens": 200,
    "stream": True,
}).encode()
req = urllib.request.Request(BASE + "/chat/completions", data=body,
                            headers={"Content-Type": "application/json"})

with urllib.request.urlopen(req) as resp:
    for raw in resp:
        line = raw.decode("utf-8").strip()
        if not line.startswith("data:"):
            continue
        data = line[5:].strip()
        if data == "[DONE]":
            break
        try:
            delta = json.loads(data)["choices"][0]["delta"]
        except (json.JSONDecodeError, KeyError, IndexError):
            continue
        piece = delta.get("content") or ""
        if piece:
            sys.stdout.write(piece)
            sys.stdout.flush()
sys.stdout.write("\n")
