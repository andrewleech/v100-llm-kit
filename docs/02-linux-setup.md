# 02, Linux setup (and WSL2)

For a **native Linux host** (the fastest setup of the lot) and for **WSL2** on Windows. If you're
on Windows, prefer [native Windows](03-windows-setup.md), it's faster than WSL2, but WSL2 works and
the steps here cover it.

Two ways to go: use the prebuilt binaries from [Releases](../../releases) (easiest), or build
from source. The card needs CUDA 12.x, **CUDA 13.3 dropped SM_70 (Volta) support**, but the
prebuilt packs bundle the CUDA runtime, so the only thing you install for them is the driver.

## Option A, prebuilt binaries

1. Download `llama.cpp-gemma4-linux-sm70.zip` and/or `ik_llama.cpp-qwen3-linux-sm70.zip`.
2. Extract, you get `bin/` plus the serve scripts.
3. [Pull a model](04-models.md), then [serve it](#serving).

The pack's `bin/` bundles the CUDA 12.x runtime (`libcudart`/`libcublas`/`libcublasLt`) next to the
engine libs, and the serve scripts put `bin/` first on `LD_LIBRARY_PATH`, so you only install an
R570–R580 driver. The driver provides `libcuda.so.1` on a native host; on WSL2 it comes through
WSL's own `libcuda.so.1`, already there. No CUDA toolkit needed for this path.

## Option B, build from source

Needs CUDA 12.x toolkit, gcc/g++, cmake 3.26+, git.

```bash
# Gemma 4 → upstream llama.cpp
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
export PATH=/usr/local/cuda-12.6/bin:$PATH CUDA_HOME=/usr/local/cuda-12.6
cmake -B build -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES="70-real" \
  -DGGML_CUDA_FORCE_MMQ=ON \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda-12.6/bin/nvcc \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc)

# Qwen3 → ik_llama.cpp (same flags)
git clone https://github.com/ikawrakow/ik_llama.cpp.git
cd ik_llama.cpp
cmake -B build -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES="70-real" \
  -DGGML_CUDA_FORCE_MMQ=ON \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda-12.6/bin/nvcc \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc)
```

Why these flags:

- `CMAKE_CUDA_ARCHITECTURES="70-real"` emits a real sm_70 cubin, no PTX-JIT surprises.
- `GGML_CUDA_FORCE_MMQ=ON` is needed on V100, it has no int8 tensor cores.
- Don't set `GGML_CUDA_IQK_FORCE_BF16=1` (ik), there's no bf16 hardware.
- Add `-DGGML_CUDA_NO_VMM=ON` only if you hit a startup OOM.

Point the serve scripts at your build with `BIN_DIR=/path/to/build/bin`.

## Serving

```bash
./serve-gemma4.sh                # Gemma 4, 32k context, port 8011
./serve-qwen3.sh                 # Qwen3, 128k context, port 8001
./serve-qwen3.sh -c 32768        # smaller context, faster TG
./serve-qwen3.sh --jinja         # tool calling on (for Claude Code)
PORT=8080 ./serve-qwen3.sh       # override port
```

Endpoints are OpenAI-compatible (`/v1/chat/completions`) and Anthropic-compatible
(`/v1/messages`), metrics at `/metrics`.

## Verify the GPU is seen

```bash
./bin/llama-cli --version
# loading a model prints:
# Device 0: Tesla V100-SXM2-16GB, compute capability 7.0, VMM: yes, VRAM: 16383 MiB
```

If you get `cannot open shared object libcuda.so.1`, the library path isn't set, use the serve
scripts, or export it yourself: `export LD_LIBRARY_PATH=/usr/lib/wsl/lib:/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH`
(drop the `wsl/lib` part on native Linux).
