#!/usr/bin/env bash
# Launch Claude Code against the local V100 server, from WSL (or native Linux).
#
# The server runs natively on Windows (start it with serve-qwen3.ps1 / serve-gemma4.ps1, or the
# .bat, using --jinja). This wrapper runs Claude Code in WSL and reaches that server over
# localhost. That requires WSL *mirrored networking*, which maps localhost in WSL to the Windows
# host. Enable it in %USERPROFILE%\.wslconfig and run `wsl --shutdown` once:
#     [wsl2]
#     networkingMode=mirrored
# Works unchanged on native Linux too (localhost is the local server).
#
# The model name matters: Claude Code injects it into the system prompt, so it's what the model
# reports when asked what it is.
#
# Usage:
#   ./claude-code.sh                            # Qwen3 (suggested), port 8001
#   ./claude-code.sh --gemma                    # Gemma 4 (faster, simple tasks), port 8011
#   ./claude-code.sh -p "what model are you?"   # extra args pass through to claude
#   HOST=1.2.3.4 ./claude-code.sh               # server on another host
set -euo pipefail

GEMMA=0
REST=()
for a in "$@"; do
  case "$a" in
    --gemma|-g) GEMMA=1 ;;
    *) REST+=("$a") ;;
  esac
done

if [ "$GEMMA" = 1 ]; then
  MODEL="Gemma-4-26B-A4B"; PORT="${PORT:-8011}"
else
  MODEL="Qwen3.6-35B-A3B"; PORT="${PORT:-8001}"
fi
HOST="${HOST:-localhost}"

export ANTHROPIC_BASE_URL="http://${HOST}:${PORT}"
export ANTHROPIC_API_KEY="sk-local"   # ignored by the local server
export ANTHROPIC_MODEL="$MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL"

echo "Claude Code -> $ANTHROPIC_BASE_URL  model=$MODEL" >&2
exec claude ${REST[@]+"${REST[@]}"}
