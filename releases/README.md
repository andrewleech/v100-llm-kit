# Release assets

Each GitHub release ships prebuilt, **SM_70 (V100) only** binaries so buyers don't need a
toolchain. One ZIP per engine per OS.

| Asset | Engine | Model | OS |
|---|---|---|---|
| `llama.cpp-gemma4-win-sm70.zip` | upstream llama.cpp | Gemma 4 | Windows native |
| `llama.cpp-gemma4-linux-sm70.zip` | upstream llama.cpp | Gemma 4 | Linux / WSL2 |
| `ik_llama.cpp-qwen3-win-sm70.zip` | ik_llama.cpp | Qwen3 | Windows native |
| `ik_llama.cpp-qwen3-linux-sm70.zip` | ik_llama.cpp | Qwen3 | Linux / WSL2 |
| `llama.cpp-dual-nvlink-win-sm70.zip` | upstream llama.cpp + NCCL | any (dual-card) | Windows native |

The last one is for the dual-V100 NVLink card, it's upstream llama.cpp built with NCCL for
tensor-parallel multi-agent serving (see [docs/07-dual-nvlink.md](../docs/07-dual-nvlink.md)). It
bundles `nccl.dll` so NCCL loads at runtime, plus `serve-dual-nccl.bat`.

> **Driver requirement (Windows).** These are **CUDA 12.8** binaries, so the NVIDIA driver must sit
> in the **R570–R580** window: R570+ (570.65) to load the GPU kernels, R580 or older for Volta/V100
> support. Too old (e.g. R535) gives `device kernel image is invalid`; past R580 drops Volta.
> Recommended **R570 573.96**. See [docs/01-hardware.md](../docs/01-hardware.md).

## ZIP contents

```
<engine>-<model>-<os>-sm70/
├── bin/                    ← llama-server, llama-bench, llama-cli (+ DLLs/libs)
├── serve-<model>.{sh,bat}  ← the matching serve script
├── download-models.{sh,bat}
├── qwen3-template-patched.jinja   ← Qwen ZIPs only
├── nccl.dll                ← dual-nvlink ZIP only (NCCL all-reduce, loaded beside the exe)
└── README.txt              ← one-liner pointing back to the repo
```

The dual-nvlink ZIP ships `serve-dual-nccl.bat` and the NCCL-enabled binaries, with `nccl.dll`
sitting in `bin/` next to `llama-server.exe` (it's loaded from the exe directory, so it has to be
there or NCCL silently falls back to the slower internal all-reduce).

## Build provenance (record per release)

- upstream llama.cpp commit: `02182fc` (Gemma 4 build tested here)
- ik_llama.cpp commit: `022bd00a` (Qwen3 build tested here)
- CUDA: 12.8 (Windows), 12.6 (Linux), both 12.x for SM_70
- Build flags: `-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=70 -DGGML_CUDA_FORCE_MMQ=ON`
- dual-nvlink build: NCCL from `SystemPanic/nccl-windows` (branch `nccl-windows`, built sm_70),
  then llama.cpp with `-DGGML_CUDA_NCCL=ON -DNCCL_ROOT=...` plus
  `-DCMAKE_CUDA_FLAGS="-DWIN32_LEAN_AND_MEAN -D_WINSOCKAPI_"` (and the same on CXX flags) to dodge
  the `nccl.h` winsock clash. Copy `nccl.dll` into `bin/`.

## TODO for packaging

- [ ] Script to assemble each ZIP from a built tree (collect bin/ + DLLs + serve script)
- [ ] Confirm which CUDA runtime DLLs must ship in the Windows ZIPs vs rely on the installer
- [ ] Checksums in the release notes
