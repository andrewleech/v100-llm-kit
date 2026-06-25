# 03, Windows native setup

Windows native is the fastest path for token generation (no WSL2 virtualisation tax, see
[benchmarks](benchmarks.md#windows-native-vs-wsl2)). Use the prebuilt binaries, or build from
source with MSVC.

**Driver, and that's the only prerequisite.** Install an **R570–R580** data-center driver (see the
driver-version note in [01-hardware.md](01-hardware.md)). Don't run a driver past R580 (it drops
Volta) or older than R570 (won't load the CUDA 12.8 kernels). The prebuilt packs bundle the CUDA
12.8 runtime DLLs and the MSVC runtime, so on a fresh Windows box the driver is all you install.
The card itself is built around CUDA 12.x, CUDA 13.3 dropped SM_70 (Volta), but you don't install
CUDA yourself for the prebuilt path. (Building from source, Option B, does need the toolkit.)

## Option A, prebuilt binaries

1. Download `llama.cpp-gemma4-win-sm70.zip` and/or `ik_llama.cpp-qwen3-win-sm70.zip`, extract.
2. [Pull a model](04-models.md), then [serve it](#serving).

The pack's `bin/` already has the CUDA 12.8 runtime (`cudart`/`cublas`/`cublasLt`) and the MSVC
runtime DLLs sitting next to `llama-server.exe`, and Windows loads DLLs from the exe's own folder
first, so it runs with no CUDA install. The serve scripts still prepend a system CUDA 12.8 `bin` to
`PATH` if you happen to have one, harmless either way.

## Option B, build from source

Prerequisites:

| Tool | How |
|---|---|
| VS Community 2022 or VS Build Tools 2022 | visualstudio.microsoft.com |
| cmake | `winget install Kitware.CMake` (or bundled with VS) |
| Ninja | `winget install Ninja-build.Ninja` |
| CUDA 12.8 | URL above |

Clone each repo to a Windows NTFS path and run its `build_windows.bat` from a plain `cmd.exe`
(the script sets up the MSVC environment itself). The kit ships both build scripts in
`scripts/windows/`. They configure with:

```
-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=70 -DGGML_CUDA_FORCE_MMQ=ON
```

**PATH gotcha:** the CUDA 12.8 installer may not update the system PATH when CUDA 13.x is already
present. If a binary starts but produces no output (a missing-DLL popup is blocking it silently),
prepend CUDA 12.8:

```
set PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin;%PATH%
```

The serve scripts handle this automatically.

## Serving

```
serve-gemma4.bat                       :: Gemma 4, 32k context, port 8011
serve-qwen3.bat                        :: Qwen3, 128k context, port 8001
set CTX=32768 & serve-qwen3.bat        :: smaller context
serve-qwen3.bat --jinja                :: tool calling on (for Claude Code)
set PORT=8080 & serve-qwen3.bat        :: override port
```

## A note on driver mode

For native Windows, leave the card in its **default TCC mode**, you don't need to change anything
and it's the best mode for compute. MCDM (the mode WSL2 needs) also runs the binaries fine if the
card's already in it, but there's no reason to switch to MCDM unless you also want WSL2, since that
costs a registry edit + reboot each way.
