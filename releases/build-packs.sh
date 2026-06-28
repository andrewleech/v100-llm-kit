#!/usr/bin/env bash
# Assemble the five V100-kit release ZIPs from already-built trees.
#
# Each pack is self-contained except for the NVIDIA display driver: the CUDA 12.8
# runtime libs (cudart/cublas/cublasLt) are bundled, and on Windows the MSVC runtime
# DLLs too. So the only prerequisite a user installs is an R570-R580 driver.
#
# Re-runnable. All source paths are overridable via the env vars below.
#
#   ./build-packs.sh            # build all five into releases/dist/
#
# Source trees (override as needed):
#   WIN_LLAMA_BIN   upstream llama.cpp Windows build bin  (Gemma + dual NCCL)
#   WIN_IK_BIN      ik_llama.cpp Windows build bin        (Qwen)
#   LIN_LLAMA_BIN   upstream llama.cpp Linux build bin    (Gemma)
#   LIN_IK_BUILD    ik_llama.cpp Linux build root         (Qwen; libs under it)
#   CUDA_WIN_BIN    CUDA 12.8 toolkit bin (Windows DLLs)
#   CUDA_LIN_LIB    CUDA 12.x toolkit lib (Linux .so)
#   WIN_SYS32       Windows System32 (MSVC runtime DLLs)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SCRIPTS="$REPO/scripts"
DIST="$HERE/dist"
mkdir -p "$DIST"
STAGE="$(mktemp -d "$DIST/.stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

WIN_LLAMA_BIN="${WIN_LLAMA_BIN:-/mnt/d/dev/llama.cpp/build/bin}"
WIN_IK_BIN="${WIN_IK_BIN:-/mnt/d/dev/ik_llama.cpp/build/bin}"
LIN_LLAMA_BIN="${LIN_LLAMA_BIN:-/home/anl/v100/llama.cpp/build/bin}"
LIN_IK_BUILD="${LIN_IK_BUILD:-/home/anl/v100/ik_llama.cpp/build}"
CUDA_WIN_BIN="${CUDA_WIN_BIN:-/mnt/c/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.8/bin}"
CUDA_LIN_LIB="${CUDA_LIN_LIB:-/usr/local/cuda-12.6/targets/x86_64-linux/lib}"
WIN_SYS32="${WIN_SYS32:-/mnt/c/Windows/System32}"

WIN_LLAMA_SRC="${WIN_LLAMA_SRC:-/mnt/d/dev/llama.cpp}"
WIN_IK_SRC="${WIN_IK_SRC:-/mnt/d/dev/ik_llama.cpp}"
LIN_LLAMA_SRC="${LIN_LLAMA_SRC:-/home/anl/v100/llama.cpp}"
LIN_IK_SRC="${LIN_IK_SRC:-/home/anl/v100/ik_llama.cpp}"

CUDA_WIN_DLLS=(cudart64_12.dll cublas64_12.dll cublasLt64_12.dll)
CUDA_LIN_SOS=(libcudart.so.12 libcublas.so.12 libcublasLt.so.12)
MSVC_DLLS=(VCRUNTIME140.dll VCRUNTIME140_1.dll MSVCP140.dll MSVCP140_CODECVT_IDS.dll MSVCP140_ATOMIC_WAIT.dll vcomp140.dll)

# Windows commits: can't run the .exe here, take the source tree HEAD (verified to match
# the binaries' embedded version). Linux commits: the build tree HEAD can drift from what
# the binary was actually built at, so read the authoritative commit from the binary's
# own --version string, falling back to git HEAD.
bin_commit() {
  local exe="$1" bindir out; bindir="$(dirname "$exe")"
  out="$(LD_LIBRARY_PATH="$bindir" "$exe" --version 2>&1 || true)"
  printf '%s\n' "$out" | grep -oE '\([0-9a-f]{7,}\)' | head -1 | tr -d '()' || true
}
ver_llama_win="$(git -C "$WIN_LLAMA_SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)"
ver_ik_win="$(git -C "$WIN_IK_SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)"
ver_llama_lin="$(bin_commit "$LIN_LLAMA_BIN/llama-server")"
ver_ik_lin="$(bin_commit "$LIN_IK_BUILD/bin/llama-server")"
[ -n "$ver_llama_lin" ] || ver_llama_lin="$(git -C "$LIN_LLAMA_SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)"
[ -n "$ver_ik_lin" ] || ver_ik_lin="$(git -C "$LIN_IK_SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)"

mkdir -p "$DIST"

# copy SRC -> DEST/, hard-fail if SRC missing (catches a moved/renamed build artifact)
cp1() {
  local src="$1" dst="$2"
  [ -e "$src" ] || { echo "MISSING: $src" >&2; exit 1; }
  cp -L "$src" "$dst"
}

# write the per-pack README.txt
write_readme() {
  local dir="$1" title="$2" prov="$3"
  cat >"$dir/README.txt" <<EOF
$title
V100 LLM Kit  --  https://github.com/andrewleech/v100-llm-kit

SM_70 (Tesla V100 / Volta) only. These will not run on other GPUs.

Prerequisite: an NVIDIA driver in the R570-R580 window (CUDA 12.8 era; R570 573.96
recommended). The CUDA runtime is bundled in bin/, so the driver is all you install.
Volta support ends after R580, and R570+ is needed to load the kernels.

CPU: needs AVX2 (Intel Haswell 2013+ / AMD Zen 2017+). No AVX-512 required.

$prov

1. Pull a model:   download-models.*   (needs a free Hugging Face account + the 'hf' CLI)
2. Serve it:       the serve-*.* script in this folder
3. OpenAI-compatible API on http://localhost:<port> -- see the repo docs.
EOF
}

# zip the staged pack dir (arg: pack base name, no extension)
# uses python zipfile (zip(1) not installed); preserves the unix exec bit for Linux packs
zip_pack() {
  local name="$1"
  STAGE="$STAGE" DIST="$DIST" PACK="$name" python3 - <<'PY'
import os, zipfile, stat
stage, dist, pack = os.environ['STAGE'], os.environ['DIST'], os.environ['PACK']
root = os.path.join(stage, pack)
out = os.path.join(dist, pack + '.zip')
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for dp, _, files in os.walk(root):
        for fn in sorted(files):
            full = os.path.join(dp, fn)
            arc = os.path.relpath(full, stage)
            z.write(full, arc)   # ZipInfo.from_file streams + preserves unix mode
PY
  echo "  -> $name.zip ($(du -h "$DIST/$name.zip" | cut -f1))"
}

echo "Staging in $STAGE ; output to $DIST"
rm -f "$DIST"/*.zip "$DIST/SHA256SUMS.txt" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 1. llama.cpp-gemma4-win-sm70  (upstream llama.cpp, NCCL build, ships nccl.dll)
# ---------------------------------------------------------------------------
build_llama_win() {
  local name="$1" serve="$2"
  local d="$STAGE/$name"
  local b="$d/bin"
  mkdir -p "$b"
  local exes=(llama-server.exe llama-cli.exe llama-bench.exe)
  local impls=(llama-server-impl.dll llama-cli-impl.dll llama-bench-impl.dll)
  local shared=(ggml.dll ggml-base.dll ggml-cpu.dll ggml-cuda.dll llama.dll llama-common.dll mtmd.dll nccl.dll)
  local f
  for f in "${exes[@]}" "${impls[@]}" "${shared[@]}"; do cp1 "$WIN_LLAMA_BIN/$f" "$b/"; done
  for f in "${CUDA_WIN_DLLS[@]}"; do cp1 "$CUDA_WIN_BIN/$f" "$b/"; done
  for f in "${MSVC_DLLS[@]}"; do cp1 "$WIN_SYS32/$f" "$b/"; done
  cp1 "$SCRIPTS/windows/$serve" "$d/"
  cp1 "$SCRIPTS/windows/download-models.bat" "$d/"
  shift 2
  # Extra files resolve from scripts/windows, falling back to scripts/wsl (claude-code.sh).
  for f in "$@"; do
    if [ -f "$SCRIPTS/windows/$f" ]; then cp1 "$SCRIPTS/windows/$f" "$d/"
    else cp1 "$SCRIPTS/wsl/$f" "$d/"; fi
  done
}

# ---------------------------------------------------------------------------
# 2. ik_llama.cpp-qwen3-win-sm70
# ---------------------------------------------------------------------------
build_ik_win() {
  local name="$1"
  local d="$STAGE/$name"
  local b="$d/bin"
  mkdir -p "$b"
  local exes=(llama-server.exe llama-cli.exe llama-bench.exe)
  local shared=(ggml.dll llama.dll mtmd.dll)
  local f
  for f in "${exes[@]}" "${shared[@]}"; do cp1 "$WIN_IK_BIN/$f" "$b/"; done
  for f in "${CUDA_WIN_DLLS[@]}"; do cp1 "$CUDA_WIN_BIN/$f" "$b/"; done
  for f in "${MSVC_DLLS[@]}"; do cp1 "$WIN_SYS32/$f" "$b/"; done
  cp1 "$SCRIPTS/windows/serve-qwen3.bat" "$d/"
  cp1 "$SCRIPTS/windows/serve-qwen3.ps1" "$d/"
  cp1 "$SCRIPTS/windows/claude-code.ps1" "$d/"
  cp1 "$SCRIPTS/wsl/claude-code.sh" "$d/"
  cp1 "$SCRIPTS/windows/download-models.bat" "$d/"
  cp1 "$SCRIPTS/windows/qwen3-template-nothink.jinja" "$d/"
  cp1 "$SCRIPTS/windows/qwen3-template-think.jinja" "$d/"
}

# ---------------------------------------------------------------------------
# 3. llama.cpp-gemma4-linux-sm70  (upstream llama.cpp)
# ---------------------------------------------------------------------------
build_llama_linux() {
  local name="$1"
  local d="$STAGE/$name"
  local b="$d/bin"
  mkdir -p "$b"
  local f
  for f in llama-server llama-cli llama-bench \
           libllama-server-impl.so libllama-cli-impl.so libllama-bench-impl.so; do
    cp1 "$LIN_LLAMA_BIN/$f" "$b/"
  done
  # shared .so (+ SONAME symlinks): ggml stack, llama, mtmd
  local g
  for g in "$LIN_LLAMA_BIN"/libggml*.so* "$LIN_LLAMA_BIN"/libllama.so* \
           "$LIN_LLAMA_BIN"/libllama-common.so* "$LIN_LLAMA_BIN"/libmtmd.so*; do
    [ -e "$g" ] && cp -a "$g" "$b/"
  done
  # bundled CUDA runtime (real file, named to its SONAME)
  for f in "${CUDA_LIN_SOS[@]}"; do cp1 "$CUDA_LIN_LIB/$f" "$b/"; done
  cp1 "$SCRIPTS/linux/serve-gemma4.sh" "$d/"
  cp1 "$SCRIPTS/linux/download-models.sh" "$d/"
  cp1 "$SCRIPTS/wsl/claude-code.sh" "$d/"
  cp1 "$SCRIPTS/linux/gemma4-template-nothink.jinja" "$d/"
  chmod +x "$b"/llama-server "$b"/llama-cli "$b"/llama-bench "$d"/*.sh
}

# ---------------------------------------------------------------------------
# 4. ik_llama.cpp-qwen3-linux-sm70
# ---------------------------------------------------------------------------
build_ik_linux() {
  local name="$1"
  local d="$STAGE/$name"
  local b="$d/bin"
  mkdir -p "$b"
  local f
  for f in llama-server llama-cli llama-bench; do cp1 "$LIN_IK_BUILD/bin/$f" "$b/"; done
  cp1 "$LIN_IK_BUILD/ggml/src/libggml.so" "$b/"
  cp1 "$LIN_IK_BUILD/src/libllama.so" "$b/"
  cp1 "$LIN_IK_BUILD/examples/mtmd/libmtmd.so" "$b/"
  for f in "${CUDA_LIN_SOS[@]}"; do cp1 "$CUDA_LIN_LIB/$f" "$b/"; done
  cp1 "$SCRIPTS/linux/serve-qwen3.sh" "$d/"
  cp1 "$SCRIPTS/linux/download-models.sh" "$d/"
  cp1 "$SCRIPTS/wsl/claude-code.sh" "$d/"
  cp1 "$SCRIPTS/linux/qwen3-template-nothink.jinja" "$d/"
  cp1 "$SCRIPTS/linux/qwen3-template-think.jinja" "$d/"
  chmod +x "$b"/llama-server "$b"/llama-cli "$b"/llama-bench "$d"/*.sh
}

prov_llama_win="upstream llama.cpp commit ${ver_llama_win}, CUDA 12.8, SM_70, -DGGML_CUDA_FORCE_MMQ=ON, GGML_NATIVE=OFF (AVX2 floor)."
prov_llama_lin="upstream llama.cpp commit ${ver_llama_lin}, CUDA 12.x, SM_70, -DGGML_CUDA_FORCE_MMQ=ON, GGML_NATIVE=OFF (AVX2 floor)."
prov_ik_win="ik_llama.cpp commit ${ver_ik_win}, CUDA 12.8, SM_70, -DGGML_CUDA_FORCE_MMQ=ON, GGML_NATIVE=OFF (AVX2 floor)."
prov_ik_lin="ik_llama.cpp commit ${ver_ik_lin}, CUDA 12.x, SM_70, -DGGML_CUDA_FORCE_MMQ=ON, GGML_NATIVE=OFF (AVX2 floor)."
prov_dual="$prov_llama_win Built with NCCL (SystemPanic/nccl-windows, sm_70), nccl.dll bundled in bin/."

echo "[1/5] llama.cpp-gemma4-win-sm70"
build_llama_win   llama.cpp-gemma4-win-sm70 serve-gemma4.bat \
                  serve-gemma4.ps1 claude-code.ps1 claude-code.sh gemma4-template-nothink.jinja
write_readme "$STAGE/llama.cpp-gemma4-win-sm70" "Gemma 4 26B-A4B  --  Windows native" "$prov_llama_win"
zip_pack llama.cpp-gemma4-win-sm70

echo "[2/5] ik_llama.cpp-qwen3-win-sm70"
build_ik_win      ik_llama.cpp-qwen3-win-sm70
write_readme "$STAGE/ik_llama.cpp-qwen3-win-sm70" "Qwen3.6 35B-A3B  --  Windows native" "$prov_ik_win"
zip_pack ik_llama.cpp-qwen3-win-sm70

echo "[3/5] llama.cpp-gemma4-linux-sm70"
build_llama_linux llama.cpp-gemma4-linux-sm70
write_readme "$STAGE/llama.cpp-gemma4-linux-sm70" "Gemma 4 26B-A4B  --  Linux / WSL2" "$prov_llama_lin"
zip_pack llama.cpp-gemma4-linux-sm70

echo "[4/5] ik_llama.cpp-qwen3-linux-sm70"
build_ik_linux    ik_llama.cpp-qwen3-linux-sm70
write_readme "$STAGE/ik_llama.cpp-qwen3-linux-sm70" "Qwen3.6 35B-A3B  --  Linux / WSL2" "$prov_ik_lin"
zip_pack ik_llama.cpp-qwen3-linux-sm70

echo "[5/5] llama.cpp-dual-nvlink-win-sm70"
build_llama_win   llama.cpp-dual-nvlink-win-sm70 serve-dual-nccl.bat \
                  bench-kv-fit.ps1 qwen3-template-nothink.jinja qwen3-template-think.jinja
write_readme "$STAGE/llama.cpp-dual-nvlink-win-sm70" "Dual V100 + NVLink (multi-agent)  --  Windows native" "$prov_dual"
zip_pack llama.cpp-dual-nvlink-win-sm70

echo "Checksums:"
( cd "$DIST" && sha256sum ./*.zip | tee SHA256SUMS.txt )

cat <<EOF

Done. Build provenance:
  upstream llama.cpp Windows (Gemma, dual): $ver_llama_win
  upstream llama.cpp Linux (Gemma):         $ver_llama_lin
  ik_llama.cpp Windows (Qwen):              $ver_ik_win
  ik_llama.cpp Linux (Qwen):                $ver_ik_lin
Output: $DIST
EOF
