# Release assets

Each GitHub release ships prebuilt, **SM_70 (V100) only** binaries so buyers don't need a
toolchain. One ZIP per engine per OS. Each pack is self-contained except for the driver: it
bundles the CUDA 12.8 runtime libs, and the Windows packs bundle the MSVC runtime too, so the
only thing a user installs is an R570–R580 NVIDIA driver.

Assemble them with [`build-packs.sh`](build-packs.sh) (re-runnable, source paths overridable via
env). It writes the five ZIPs + `SHA256SUMS.txt` into `releases/dist/` (gitignored), ready to
attach to a GitHub release.

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

> **Driver requirement.** These are **CUDA 12.8** binaries, so the NVIDIA driver must sit in the
> **R570–R580** window: R570+ (570.65) to load the GPU kernels, R580 or older for Volta/V100
> support. Too old (e.g. R535) gives `device kernel image is invalid`; past R580 drops Volta.
> Recommended **R570 573.96**. The CUDA runtime itself is bundled in the pack, so the driver is the
> only prerequisite. See [docs/01-hardware.md](../docs/01-hardware.md).

## ZIP contents

```
<engine>-<model>-<os>-sm70/
├── bin/
│   ├── llama-server, llama-cli, llama-bench   ← curated set (+ their -impl libs on upstream llama.cpp)
│   ├── ggml*/llama*/mtmd libs                 ← the engine's own shared libs
│   ├── cudart64_12 / cublas64_12 / cublasLt64_12 (.dll)   ← bundled CUDA 12.8 runtime (Windows)
│   │   └─ or libcudart/libcublas/libcublasLt.so.12        ← bundled CUDA 12.x runtime (Linux)
│   ├── VCRUNTIME140*/MSVCP140*/vcomp140 (.dll)            ← bundled MSVC runtime (Windows only)
│   └── nccl.dll                               ← Windows llama.cpp packs only (loaded beside the exe)
├── serve-<model>.{sh,bat}  ← the matching serve script
├── download-models.{sh,bat}
├── *-template-*.jinja      ← Gemma packs ship gemma4-template-nothink; Qwen/dual ship the qwen3 templates
└── README.txt              ← provenance + driver requirement, points back to the repo
```

Only a curated binary set ships (server/cli/bench), not the whole build tree of tools and tests.

The dual-nvlink ZIP ships `serve-dual-nccl.bat` and the NCCL-enabled binaries, with `nccl.dll`
sitting in `bin/` next to `llama-server.exe` (it's loaded from the exe directory, so it has to be
there or NCCL silently falls back to the slower internal all-reduce). The single-card Gemma Windows
pack is built from the same NCCL-enabled tree, whose `ggml-cuda.dll` statically imports `nccl.dll`,
so it ships `nccl.dll` too (loaded but idle on a single card).

## Build provenance (record per release)

- upstream llama.cpp commit: `02182fc` (Gemma 4 + dual-nvlink, Windows and Linux)
- ik_llama.cpp commit: `022bd00a` (Qwen3, Windows and Linux). `build-packs.sh` reads the Linux
  commit from the binary's own `--version` rather than the tree HEAD, since the build tree can
  drift ahead of what the shipped binary was built at.
- CUDA: 12.8 (Windows), 12.6 (Linux), both 12.x for SM_70. The runtime libs are bundled, sourced
  from the toolkit install (`…/CUDA/v12.8/bin` on Windows, `/usr/local/cuda-12.6/…/lib` on Linux).
- Build flags: `-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=70 -DGGML_CUDA_FORCE_MMQ=ON`
- CPU floor: built `-DGGML_NATIVE=OFF` with an explicit `-DGGML_AVX2=ON -DGGML_FMA=ON
  -DGGML_F16C=ON -DGGML_BMI2=ON` (MSVC `/arch:AVX2`). Portable to any AVX2 CPU (Haswell 2013+ /
  Zen 2017+), no AVX-512. `-march=native` is avoided so the binaries don't pick up host-only
  (e.g. znver2) instructions an older AVX2 CPU would fault on. Reproducible via the scripts in
  [`../build/`](../build/); see [build/README.md](../build/README.md).
- dual-nvlink build: NCCL from `SystemPanic/nccl-windows` (branch `nccl-windows`, built sm_70),
  then llama.cpp with `-DGGML_CUDA_NCCL=ON -DNCCL_ROOT=...` plus
  `-DCMAKE_CUDA_FLAGS="-DWIN32_LEAN_AND_MEAN -D_WINSOCKAPI_"` (and the same on CXX flags) to dodge
  the `nccl.h` winsock clash. Copy `nccl.dll` into `bin/`.

## Bundling decision

CUDA runtime libs (cudart, cublas, cublasLt) and the Windows MSVC runtime are **bundled into the
packs** rather than required as a separate install. NVIDIA's redistributable list permits shipping
the CUDA runtime, and Microsoft's the MSVC runtime, so a fresh machine needs only an R570–R580
driver. The cost is size: `cublasLt` alone is ~500–690 MB, which is why each pack is 0.5–0.75 GB.
The driver is never bundled (machine-specific, not redistributable, and the version window is the
one thing a user has to get right anyway).

`build-packs.sh` verifies what to bundle by reading each binary's actual import table (Windows) /
`ldd` (Linux), not by guessing. The Windows ggml libs pull in `vcomp140.dll` (the VC++ OpenMP
runtime) on top of the usual `VCRUNTIME140*`/`MSVCP140*`, so that's bundled too.

## Checksums

`build-packs.sh` writes `SHA256SUMS.txt` alongside the ZIPs in `releases/dist/`. Paste it into the
GitHub release notes so downloads can be verified with `sha256sum -c`.
