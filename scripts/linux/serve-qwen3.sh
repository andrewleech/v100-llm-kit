#!/usr/bin/env bash
# Serve Qwen3.6-35B-A3B (ik_llama.cpp) on a V100. Linux native or WSL2.
#
# Layout (override with env): binaries in $BIN_DIR, model in $MODEL. Defaults are relative
# to this script, matching how the release ZIP extracts.
#
# Usage:
#   ./serve-qwen3.sh                 # 128k context
#   ./serve-qwen3.sh -c 32768        # smaller context, faster TG
#   ./serve-qwen3.sh --jinja         # tool calling on (needed for Claude Code)
#   PORT=8080 ./serve-qwen3.sh       # override port
# Extra args pass straight through to llama-server.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HERE/bin}"
MODEL="${MODEL:-$HERE/models/qwen3.6-35b-a3b-MTP-GGUF/Qwen3.6-35B-A3B-IQ4_XS-4.19bpw.gguf}"
PORT="${PORT:-8001}"
KV="${KV:-q8_0}"
CTX=131072

ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -c|--ctx-size) CTX="$2"; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

if [ "$CTX" -gt 131072 ]; then MARGIN="${FIT_MARGIN:-2048}"; else MARGIN="${FIT_MARGIN:-1664}"; fi

# With tool calling (--jinja), default to the bundled no-think template — thinking adds big
# latency for agentic use. Skipped if you already passed --chat-template-file, or set THINK=1
# to use the model's default (thinking-on) template instead.
case " ${ARGS[*]} " in *" --jinja "*) JINJA=1 ;; *) JINJA=0 ;; esac
case " ${ARGS[*]} " in *" --chat-template-file "*) HAVE_TPL=1 ;; *) HAVE_TPL=0 ;; esac
if [ "$JINJA" = 1 ] && [ "$HAVE_TPL" = 0 ] && [ "${THINK:-0}" != 1 ]; then
  ARGS+=(--chat-template-file "$HERE/qwen3-template-nothink.jinja")
fi

# Build the library path: WSL GPU libs if present (WSL2), plus any CUDA runtime dir.
LIBS=""
[ -d /usr/lib/wsl/lib ] && LIBS="/usr/lib/wsl/lib"
for d in /usr/local/cuda-12.6/lib64 /usr/local/cuda-12/lib64 /usr/local/cuda/lib64; do
  [ -d "$d" ] && LIBS="${LIBS:+$LIBS:}$d"
done
export LD_LIBRARY_PATH="${LIBS:+$LIBS:}${LD_LIBRARY_PATH:-}"

[ -f "$MODEL" ] || { echo "model not found: $MODEL  (run download-models.sh)" >&2; exit 1; }
echo "serving qwen3 ctx=${CTX} margin=${MARGIN} port=${PORT}" >&2

exec "$BIN_DIR/llama-server" \
  -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" \
  -ngl 99 -fa on \
  -b 2048 -ub 2048 \
  --fit --fit-margin "$MARGIN" \
  -ctk "$KV" -ctv "$KV" -ctkd "$KV" -ctvd "$KV" \
  -cram "${CRAM:-16384}" \
  --spec-type mtp:n_max=3,p_min=0.75 \
  -c "$CTX" \
  --no-mmap --mlock \
  -t "${THREADS:-12}" \
  --parallel 1 --metrics \
  "${ARGS[@]}"
