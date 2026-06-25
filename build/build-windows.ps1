# Build the V100 (sm_70) Windows binaries from the pinned submodule sources.
#
# Host-agnostic: no absolute paths. Resolves the repo root relative to this
# script, builds into build\out\, and relies on CUDA 12.8 (CUDA_PATH) and an
# active VS2022 x64 dev environment (run from "x64 Native Tools Command
# Prompt" or after vcvars64.bat). Override CUDA_ARCH / NATIVE via env.
#
#   pwsh build\build-windows.ps1 [-Target nccl|llama|ik|all]
#
# Pinned sources (see ..\.gitmodules):
#   external\llama.cpp     ggml-org/llama.cpp @ 02182fc      -> Gemma 4 + dual-NVLink packs
#   external\ik_llama.cpp  ikawrakow/ik_llama.cpp @ 022bd00a -> Qwen3 pack
#   external\nccl-windows  SystemPanic/nccl-windows @ f22ac6e -> NCCL for the dual card
param([string]$Target = 'all')

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Out  = Join-Path $PSScriptRoot 'out'
$Arch   = if ($env:CUDA_ARCH) { $env:CUDA_ARCH } else { '70' }
# Redistributable binaries default to GGML_NATIVE=OFF so they run on any
# x86-64 CPU. Set NATIVE=ON to reproduce a host-tuned build for this machine.
$Native = if ($env:NATIVE)    { $env:NATIVE }    else { 'OFF' }

# Portable instruction floor for the NATIVE=OFF case: AVX2 + FMA + F16C + BMI2
# (Intel Haswell 2013+ / AMD Zen 2017+). MSVC maps this to /arch:AVX2. No AVX-512.
$Simd = if ($Native -eq 'OFF') { @('-DGGML_AVX2=ON','-DGGML_FMA=ON','-DGGML_F16C=ON','-DGGML_BMI2=ON') } else { @() }

git -C $Root submodule update --init external/llama.cpp external/ik_llama.cpp external/nccl-windows

$Nccl        = Join-Path $Root 'external\nccl-windows'
$NcclInstall = Join-Path $Nccl 'install'

function Build-Nccl {
  # NVIDIA ships no Windows NCCL, build the community port (sm_70) and install
  # it where the llama.cpp configure step can find it.
  cmake -S $Nccl -B (Join-Path $Out 'nccl-windows') -G Ninja `
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=$Arch `
    -DCMAKE_INSTALL_PREFIX=$NcclInstall
  cmake --build (Join-Path $Out 'nccl-windows') --parallel --target install
  Write-Host ">> nccl-windows: $NcclInstall\bin\nccl.dll"
}

function Build-Llama {
  # Upstream llama.cpp with NCCL. Serves both the Gemma single-card pack and the
  # dual-NVLink pack, the difference at runtime is whether GGML_CUDA_ALLREDUCE=nccl
  # and -sm tensor are set (see docs/07-dual-nvlink.md). nccl.dll is copied beside
  # the binaries because ggml-cuda.dll imports it at load time.
  if (-not (Test-Path (Join-Path $NcclInstall 'bin\nccl.dll'))) { Build-Nccl }
  $bld = Join-Path $Out 'llama.cpp-win'
  cmake -S (Join-Path $Root 'external\llama.cpp') -B $bld -G Ninja `
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=$Arch `
    -DGGML_CUDA=ON -DGGML_CUDA_FA=ON -DGGML_CUDA_FORCE_MMQ=ON -DGGML_NATIVE=$Native $Simd `
    -DGGML_CUDA_NCCL=ON -DNCCL_ROOT=$NcclInstall `
    -DCMAKE_CUDA_FLAGS='-DWIN32_LEAN_AND_MEAN -D_WINSOCKAPI_' `
    -DCMAKE_CXX_FLAGS='-DWIN32_LEAN_AND_MEAN -D_WINSOCKAPI_'
  cmake --build $bld --parallel --target llama-server --target llama-cli --target llama-bench
  Copy-Item (Join-Path $NcclInstall 'bin\nccl.dll') (Join-Path $bld 'bin') -Force
  Write-Host ">> llama.cpp (win): $bld\bin"
}

function Build-Ik {
  # ik_llama.cpp, Qwen3 MoE expert offload. No NCCL.
  $bld = Join-Path $Out 'ik_llama.cpp-win'
  cmake -S (Join-Path $Root 'external\ik_llama.cpp') -B $bld -G Ninja `
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=$Arch `
    -DGGML_CUDA=ON -DGGML_CUDA_F16=OFF -DGGML_CUDA_FORCE_MMQ=ON `
    -DGGML_NATIVE=$Native -DLLAMA_CURL=OFF $Simd
  cmake --build $bld --parallel --target llama-server --target llama-cli --target llama-bench
  Write-Host ">> ik_llama.cpp (win): $bld\bin"
}

switch ($Target) {
  'nccl'  { Build-Nccl }
  'llama' { Build-Llama }
  'ik'    { Build-Ik }
  'all'   { Build-Nccl; Build-Llama; Build-Ik }
  default { throw "usage: build-windows.ps1 -Target nccl|llama|ik|all" }
}
