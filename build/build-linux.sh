#!/usr/bin/env bash
# Build the V100 (sm_70) Linux binaries from the pinned submodule sources.
#
# Host-agnostic: no absolute paths. Resolves the repo root relative to this
# script, builds into build/out/, and finds CUDA via nvcc on PATH (or CUDA_PATH
# / the default cmake search). Override JOBS, CUDA_ARCH or NATIVE via env.
#
#   ./build/build-linux.sh [llama|ik|all]
#
# Pinned sources (see ../.gitmodules):
#   external/llama.cpp     ggml-org/llama.cpp @ 02182fc   -> Gemma 4 pack
#   external/ik_llama.cpp  ikawrakow/ik_llama.cpp @ 022bd00a -> Qwen3 pack
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
OUT="$SCRIPT_DIR/out"
JOBS="${JOBS:-$(nproc)}"
# V100 is compute 7.0 only. The "-real" suffix emits SASS without the PTX, so
# the binary carries sm_70 cubins and nothing else.
CUDA_ARCH="${CUDA_ARCH:-70-real}"
# Redistributable binaries default to GGML_NATIVE=OFF so they run on any
# x86-64 CPU. Set NATIVE=ON to reproduce a host-tuned build for this machine.
NATIVE="${NATIVE:-OFF}"

# Portable instruction floor for the NATIVE=OFF case: AVX2 + FMA + F16C + BMI2
# (Intel Haswell 2013+ / AMD Zen 2017+), the highest set a CPU paired with a
# V100 reliably has. No AVX-512. Without this, -march=native would bake in the
# build host's full ISA (e.g. znver2 instructions older AVX2 CPUs lack).
SIMD=()
if [ "$NATIVE" = "OFF" ]; then
  SIMD=(-DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_BMI2=ON)
fi

command -v cmake >/dev/null || { echo "cmake not found on PATH" >&2; exit 1; }
command -v nvcc  >/dev/null || echo "warning: nvcc not on PATH, relying on CUDA_PATH / cmake CUDA search" >&2
# Prefer Ninja if installed, fall back to Make so a bare box still builds.
GEN="${GEN:-$(command -v ninja >/dev/null 2>&1 && echo Ninja || echo 'Unix Makefiles')}"

git -C "$ROOT" submodule update --init external/llama.cpp external/ik_llama.cpp

build_llama() {  # upstream llama.cpp -> Gemma 4 pack (single card, no NCCL)
  local src="$ROOT/external/llama.cpp" bld="$OUT/llama.cpp-linux"
  cmake -S "$src" -B "$bld" -G "$GEN" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH" \
    -DGGML_CUDA=ON -DGGML_CUDA_FA=ON -DGGML_CUDA_FORCE_MMQ=ON \
    -DGGML_CUDA_NCCL=OFF -DGGML_NATIVE="$NATIVE" "${SIMD[@]}"
  cmake --build "$bld" -j "$JOBS" --target llama-server --target llama-cli --target llama-bench
  echo ">> llama.cpp (linux): $bld/bin"
}

build_ik() {  # ik_llama.cpp -> Qwen3 pack (MoE expert offload)
  local src="$ROOT/external/ik_llama.cpp" bld="$OUT/ik_llama.cpp-linux"
  cmake -S "$src" -B "$bld" -G "$GEN" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH" \
    -DGGML_CUDA=ON -DGGML_CUDA_F16=OFF -DGGML_CUDA_FORCE_MMQ=ON \
    -DGGML_NATIVE="$NATIVE" -DLLAMA_CURL=OFF "${SIMD[@]}"
  cmake --build "$bld" -j "$JOBS" --target llama-server --target llama-cli --target llama-bench
  echo ">> ik_llama.cpp (linux): $bld/bin"
}

case "${1:-all}" in
  llama) build_llama ;;
  ik)    build_ik ;;
  all)   build_llama; build_ik ;;
  *) echo "usage: $0 [llama|ik|all]" >&2; exit 2 ;;
esac
