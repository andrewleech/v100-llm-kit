#!/usr/bin/env bash
# Serve a Q6_K 35B coding model (Qwen3.6-35B-A3B or Ornith-1.0-35B) RESIDENT across both
# V100s on upstream llama.cpp. Linux native or WSL2.
#
# This is the production quality serve for the 35B coding models. Q6_K (~29 GB) fits in the
# 32 GB across two cards with -sm layer -ts 1/1, so the whole model stays in VRAM (no expert
# offload to CPU RAM). KV is cheap on this hybrid model, so a big shared pool is affordable.
# Decode ~80 tok/s. --kv-unified is REQUIRED for the cross-slot shared-prefix feature.
#
# Layout (override with env): binaries in $BIN_DIR, model in $MODEL. Defaults are relative
# to this script, matching how the release ZIP extracts.
#
# Usage:
#   ./serve-q6-resident.sh                 # 4 slots x 32k (128k total), port 8011
#   ./serve-q6-resident.sh -c 65536        # smaller total context
#   ./serve-q6-resident.sh --jinja         # tool calling on (needed for Claude Code)
#   PORT=8080 ./serve-q6-resident.sh       # override port
#   PARALLEL=8 ./serve-q6-resident.sh      # 8 concurrent slots
# Extra args pass straight through to llama-server.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HERE/bin}"
MODEL="${MODEL:-$HERE/models/qwen3.6-35b-a3b-MTP-GGUF/Qwen3.6-35B-A3B-Q6_K.gguf}"
PORT="${PORT:-8011}"
PARALLEL="${PARALLEL:-4}"
KV="${KV:-q8_0}"
CTX=131072

ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -c|--ctx-size) CTX="$2"; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

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
echo "serving q6-resident ctx=${CTX} parallel=${PARALLEL} kv=${KV} port=${PORT}" >&2

exec "$BIN_DIR/llama-server" \
  -m "$MODEL" \
  --host 0.0.0.0 --port "$PORT" \
  -ngl 99 -fa on \
  -sm layer -ts 1/1 \
  -ctk "$KV" -ctv q8_0 \
  -c "$CTX" --kv-unified \
  --cont-batching --parallel "$PARALLEL" --metrics \
  "${ARGS[@]}"
