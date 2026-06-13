# 03 — Windows native setup

Windows native is the fastest path for token generation (no WSL2 virtualisation tax — see
[benchmarks](benchmarks.md#windows-native-vs-wsl2)). Use the prebuilt binaries, or build from
source with MSVC.

**CUDA requirement: V100 needs CUDA 12.8.** CUDA 13.0+ dropped SM_70 (Volta) support. CUDA 12.x
and 13.x install side-by-side fine.

## Option A — prebuilt binaries

1. Install the CUDA 12.8 **runtime** (the serve scripts need the DLLs):
   ```
   https://developer.download.nvidia.com/compute/cuda/12.8.0/local_installers/cuda_12.8.0_571.96_windows.exe
   ```
   Run it elevated (double-click, accept UAC). Installs to
   `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\`.
2. Download `llama.cpp-gemma4-win-sm70.zip` and/or `ik_llama.cpp-qwen3-win-sm70.zip`, extract.
3. [Pull a model](04-models.md), then [serve it](#serving).

The serve scripts prepend the CUDA 12.8 `bin` to `PATH` so the binaries find their DLLs even
when CUDA 13.x is also installed.

## Option B — build from source

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

The Windows binaries run against the V100 in whatever mode the driver's in. MCDM (the mode WSL2
needs) works fine. TCC mode might give a touch more CUDA performance for a Windows-only setup,
but switching back to MCDM is a registry edit + reboot, so only go there if you've committed to
Windows-only and want to chase the last few percent.
