# Building from source

The prebuilt binaries in [Releases](../../../releases) are what most people want. This is here if
you want to rebuild them yourself, or build for a different CUDA version.

The engines are pinned as git submodules in [`external/`](../external), so the source is the exact
commit each release was built from. Nothing here is patched, the V100 support is all build flags
plus the community NCCL port, not source edits.

| Submodule | Upstream | Commit | Used for |
|---|---|---|---|
| `external/llama.cpp` | ggml-org/llama.cpp | `02182fc` | Gemma 4 pack, and (on Windows, +NCCL) the dual-NVLink pack |
| `external/ik_llama.cpp` | ikawrakow/ik_llama.cpp | `022bd00a` | Qwen3 pack |
| `external/nccl-windows` | SystemPanic/nccl-windows | `f22ac6e` | NCCL for the dual V100 card (Windows only) |

Pull them with:

```
git submodule update --init
```

## Prerequisites

- **CUDA toolkit** with `nvcc`. Windows: 12.8 (matches the release binaries). Linux: any 12.x that
  still supports Volta (12.6 here). The driver still has to sit in the R570-R580 window, see
  [docs/01-hardware.md](../docs/01-hardware.md).
- **CMake** and **Ninja**.
- **Windows:** Visual Studio 2022 (x64). Run the build from an "x64 Native Tools Command Prompt"
  (or after `vcvars64.bat`) so `cl.exe` and the CUDA host compiler line up.

## Build

Linux:

```
./build/build-linux.sh            # both engines, output in build/out/<engine>-linux/bin
./build/build-linux.sh llama      # just llama.cpp (Gemma)
./build/build-linux.sh ik         # just ik_llama.cpp (Qwen)
```

Windows (PowerShell, from a VS2022 x64 dev prompt):

```
pwsh build\build-windows.ps1                  # nccl-windows, then both engines
pwsh build\build-windows.ps1 -Target ik       # just ik_llama.cpp
```

On Windows the NCCL port builds first into `external/nccl-windows/install`, then llama.cpp is
configured against it and `nccl.dll` is copied beside the binaries (ggml-cuda.dll imports it at
load time, so it has to be there even for single-card use).

## CPU portability (GGML_NATIVE)

Both scripts default to `GGML_NATIVE=OFF` and pin an explicit instruction floor of **AVX2 + FMA +
F16C + BMI2** (Intel Haswell 2013+ / AMD Zen 2017+, MSVC `/arch:AVX2`). That's the highest set a CPU
paired with a V100 reliably has, so the binaries run anywhere with AVX2 but still use it. There's no
AVX-512 (the build host, a Zen2, has none anyway).

The release binaries use this floor. The CPU only does real compute on the Qwen pack (ik_llama
offloads MoE experts to CPU), so AVX2 matters there; the Gemma pack is GPU-only and barely touches
it. Building with `-march=native` instead would only add host-specific tuning (and on Linux, znver2
instructions older AVX2 CPUs lack), for no real speed gain here. If you do want a host-tuned build
for one specific machine, set `NATIVE=ON`:

```
NATIVE=ON ./build/build-linux.sh          # Linux
$env:NATIVE='ON'; pwsh build\build-windows.ps1   # Windows
```

The architecture is fixed to **sm_70** (`CUDA_ARCH`/`-DCMAKE_CUDA_ARCHITECTURES=70`), the only thing
a V100 runs. Override `CUDA_ARCH` only if you know you want a different card.
