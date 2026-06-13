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
PROMPT="$(grep -v '^#' "$SCENARIO_FILE" | grep -v '^[[:space:]]*$' | head -1)"

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

# Type the prompt, then submit.
tmux send-keys -t "$SESSION" -l "$PROMPT"
sleep 1.5
tmux send-keys -t "$SESSION" Enter

# Poll the pane: wait until we've seen the "working" indicator appear and then disappear,
# i.e. generation started and finished. Falls back to MAX_WAIT.
echo "waiting for reply to finish (max ${MAX_WAIT}s)..." >&2
# While generating, Claude Code shows a gerund spinner ("✻ Osmosing…"); when done it shows a
# past-tense summary line ("✻ Worked for 12s"). The "for <N>s" summary is the clean done signal.
waited=0
sleep 4   # let generation start before we start checking for the done summary
while [ "$waited" -lt "$MAX_WAIT" ]; do
  pane="$(tmux capture-pane -t "$SESSION" -p 2>/dev/null || true)"
  if echo "$pane" | grep -qiE "for [0-9]+s\b"; then
    break   # "✻ Worked for Ns" → reply finished
  fi
  sleep 2; waited=$((waited+2))
done
sleep 3   # let the final answer settle fully on screen

# End the recording ON the answer: kill the session so the read-only attach exits. No /exit,
# which would clear the view to a "Resume this session" screen and ruin the final frame.
cleanup
wait "$REC_PID" 2>/dev/null || true

echo "recorded: $CAST  (${waited}s wait)" >&2
echo "convert to gif: ./cast-to-gif.sh $CAST" >&2
