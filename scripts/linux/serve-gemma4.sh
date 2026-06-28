#!/usr/bin/env bash
# Serve Gemma 4 26B-A4B QAT (upstream llama.cpp) on a V100. Linux native or WSL2.
#
# Fits entirely in 16 GB VRAM, no CPU offload. Layout overridable via $BIN_DIR / $MODEL.
#
# Usage:
#   ./serve-gemma4.sh                # 32k context
#   ./serve-gemma4.sh -c 131072      # 128k (bigger KV, still fits 16GB)
#   PORT=8011 ./serve-gemma4.sh      # override port
# Extra args pass straight through to llama-server.
#
# Notes:
# - -t 6 beats -t 12 for TG here: the model's fully GPU-resident so extra threads only add
#   scheduling overhead. Override with THREADS=N.
# - -ub 1024 beats the 512 default for prompt processing on longer prompts.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HERE/bin}"
MODEL="${MODEL:-$HERE/models/gemma-4-26B-A4B-qat/gemma-4-26B_q4_0-it.gguf}"
PORT="${PORT:-8011}"
KV="${KV:-q8_0}"
CTX=32768

ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -c|--ctx-size) CTX="$2"; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

# With tool calling (--jinja), default to the bundled no-think template (thinking adds latency
# for agentic use). Skipped if you passed --chat-template-file, or set THINK=1 for thinking-on.
case " ${ARGS[*]} " in *" --jinja "*) JINJA=1 ;; *) JINJA=0 ;; esac
case " ${ARGS[*]} " in *" --chat-template-file "*) HAVE_TPL=1 ;; *) HAVE_TPL=0 ;; esac
if [ "$JINJA" = 1 ] && [ "$HAVE_TPL" = 0 ] && [ "${THINK:-0}" != 1 ]; then
  ARGS+=(--chat-template-file "$HERE/gemma4-template-nothink.jinja")
fi

LIBS=""
[ -d /usr/lib/wsl/lib ] && LIBS="/usr/lib/wsl/lib"
for d in /usr/local/cuda-12.6/lib64 /usr/local/cuda-12/lib64 /usr/local/cuda/lib64; do
  [ -d "$d" ] && LIBS="${LIBS:+$LIBS:}$d"
done
export LD_LIBRARY_PATH="${BIN_DIR}${LIBS:+:$LIBS}:${LD_LIBRARY_PATH:-}"

[ -f "$MODEL" ] || { echo "model not found: $MODEL  (run download-models.sh)" >&2; exit 1; }
echo "serving gemma4 ctx=${CTX} port=${PORT}" >&2

exec "$BIN_DIR/llama-server" \
  -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" \
  -ngl 99 -fa 1 \
  -b 2048 -ub 1024 \
  -ctk "$KV" -ctv "$KV" \
  -c "$CTX" \
  -t "${THREADS:-6}" \
  --parallel 1 --metrics \
  "${ARGS[@]}"
