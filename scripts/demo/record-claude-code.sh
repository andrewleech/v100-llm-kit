#!/usr/bin/env bash
# Record a Claude Code session against the local V100 model with asciinema.
#
# Drives an interactive `claude` TUI inside a fixed-size tmux pane, types a prompt, waits
# for the reply to actually finish (polls the pane, not a fixed sleep), then exits cleanly.
# asciinema captures it to a .cast which cast-to-gif.sh turns into a gif.
#
# Prereqs: a model server on $ANTHROPIC_BASE_URL, and the demo folder pre-trusted + the
# custom API key pre-approved in ~/.claude.json (otherwise the first-run prompts block it).
# Set ANTHROPIC_MODEL to the REAL model name so Claude Code reports it honestly (see docs/05).
#
# Usage:
#   ANTHROPIC_BASE_URL=http://localhost:8001 ANTHROPIC_MODEL="Qwen3.6-35B-A3B" \
#     ./record-claude-code.sh <scenario> [workdir]
#   scenario = what-model | project-query   (see scenarios/)

set -euo pipefail

SCENARIO="${1:-what-model}"
WORKDIR="${2:-$PWD}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$HERE/../../assets/casts"
mkdir -p "$OUT_DIR"
CAST="$OUT_DIR/claude-${SCENARIO}.cast"

SCENARIO_FILE="$HERE/scenarios/${SCENARIO}.md"
[ -f "$SCENARIO_FILE" ] || { echo "no scenario file: $SCENARIO_FILE" >&2; exit 1; }
# Each non-comment, non-blank line is one turn (prompt). Multi-line scenarios drive a
# multi-turn session: type a prompt, wait for the reply, then the next.
mapfile -t PROMPTS < <(grep -v '^#' "$SCENARIO_FILE" | grep -v '^[[:space:]]*$')
[ "${#PROMPTS[@]}" -gt 0 ] || { echo "no prompts in $SCENARIO_FILE" >&2; exit 1; }

: "${ANTHROPIC_BASE_URL:?set ANTHROPIC_BASE_URL to the local server first}"
MODEL_NAME="${ANTHROPIC_MODEL:-local}"
MAX_WAIT="${MAX_WAIT:-200}"     # hard cap on waiting for the reply
COLS=100; ROWS=32
SESSION="ccdemo"

cleanup() { tmux kill-session -t "$SESSION" 2>/dev/null || true; }
trap cleanup EXIT
cleanup

# Build the env the claude process runs under.
ENV_PREFIX=""
[ -n "${CLAUDE_CONFIG_DIR:-}" ] && ENV_PREFIX="CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' "
ENV_PREFIX="${ENV_PREFIX}ANTHROPIC_BASE_URL='$ANTHROPIC_BASE_URL' ANTHROPIC_API_KEY='${ANTHROPIC_API_KEY:-sk-local}'"
for v in ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL \
         ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL; do
  ENV_PREFIX="$ENV_PREFIX $v='$MODEL_NAME'"
done

# Fixed-size session with no status bar and manual sizing, so the capture is clean (no tmux
# chrome, no size-mismatch dots).
# CLAUDE_ARGS lets a scenario pass flags to claude, e.g. --permission-mode bypassPermissions
# so a read-only tool call (ls) in the project-query demo runs without a permission prompt.
tmux new-session -d -s "$SESSION" -x "$COLS" -y "$ROWS" -c "$WORKDIR" "$ENV_PREFIX claude ${CLAUDE_ARGS:-}"
tmux set-option -t "$SESSION" status off
tmux set-option -t "$SESSION" -g window-size manual 2>/dev/null || true
tmux resize-window -t "$SESSION" -x "$COLS" -y "$ROWS" 2>/dev/null || true
sleep 6   # let the TUI draw

# Record the attached (read-only) view while we drive keystrokes from outside.
asciinema rec --overwrite --cols "$COLS" --rows "$ROWS" \
  -c "tmux attach -t $SESSION -r" "$CAST" &
REC_PID=$!
sleep 2

# Each completed turn leaves a "✻ <verb> for <N>s" summary. Counting those (including
# scrollback) tells us how many turns have finished, which is robust across multiple turns.
done_count() { tmux capture-pane -t "$SESSION" -p -S -400 2>/dev/null | grep -cE "for [0-9]+s\b"; }

turn=0
for PROMPT in "${PROMPTS[@]}"; do
  turn=$((turn+1))
  tmux send-keys -t "$SESSION" -l "$PROMPT"
  sleep 1.2
  tmux send-keys -t "$SESSION" Enter
  echo "turn $turn/${#PROMPTS[@]}: waiting for reply (max ${MAX_WAIT}s)..." >&2
  waited=0
  sleep 3   # let generation start
  while [ "$waited" -lt "$MAX_WAIT" ]; do
    [ "$(done_count)" -ge "$turn" ] && break   # this turn's summary has appeared
    sleep 2; waited=$((waited+2))
  done
  sleep 2.5   # let the answer settle and read on screen before the next prompt
done
sleep 1

# End the recording ON the answer: kill the session so the read-only attach exits. No /exit,
# which would clear the view to a "Resume this session" screen and ruin the final frame.
cleanup
wait "$REC_PID" 2>/dev/null || true

echo "recorded: $CAST  (${waited}s wait)" >&2
echo "convert to gif: ./cast-to-gif.sh $CAST" >&2
