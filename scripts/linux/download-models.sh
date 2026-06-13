#!/usr/bin/env bash
# Pull the GGUF models into ./models. Needs a free Hugging Face account + token
# (https://huggingface.co/settings/tokens), and the `hf` CLI:
#   pip install -U "huggingface_hub[hf_transfer]"
#
# Usage:
#   ./download-models.sh            # both models
#   ./download-models.sh gemma      # just Gemma 4
#   ./download-models.sh qwen       # just Qwen3
#
# Models MUST live on the native filesystem of the OS running llama.cpp. On WSL2 keep them
# on ext4 (here), never on /mnt/c or /mnt/d — NTFS-over-9p is 3-5x slower for mmap.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${MODEL_DIR:-$HERE/models}"
WHICH="${1:-all}"

command -v hf >/dev/null || { echo "hf CLI not found. pip install -U 'huggingface_hub[hf_transfer]'" >&2; exit 1; }
export HF_HUB_ENABLE_HF_TRANSFER=1
[ -n "${HF_TOKEN:-}" ] || { [ -f ~/.cache/huggingface/token ] && export HF_TOKEN="$(cat ~/.cache/huggingface/token)"; }

pull_gemma() {
  echo ">> Gemma 4 26B-A4B QAT Q4_0 (~13.4 GB)" >&2
  hf download google/gemma-4-26B-A4B-it-qat-q4_0-gguf \
    gemma-4-26B_q4_0-it.gguf \
    --local-dir "$DEST/gemma-4-26B-A4B-qat"
}

pull_qwen() {
  echo ">> Qwen3.6 35B-A3B IQ4_XS (~18.6 GB)" >&2
  hf download byteshape/Qwen3.6-35B-A3B-MTP-GGUF \
    Qwen3.6-35B-A3B-IQ4_XS-4.19bpw.gguf \
    --local-dir "$DEST/qwen3.6-35b-a3b-MTP-GGUF"
}

case "$WHICH" in
  gemma) pull_gemma ;;
  qwen)  pull_qwen ;;
  all)   pull_gemma; pull_qwen ;;
  *) echo "usage: $0 [gemma|qwen|all]" >&2; exit 1 ;;
esac
echo "done. models in $DEST" >&2
