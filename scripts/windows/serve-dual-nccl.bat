@echo off
:: Serve a model across TWO V100s with NVLink, tensor-parallel + NCCL all-reduce.
:: For multi-agent / high-concurrency use: NCCL over NVLink gives ~2x prompt-processing
:: and meaningfully higher decode throughput under concurrency vs the Windows-default
:: ("internal") all-reduce. See docs/benchmarks.md "Dual V100 + NVLink (multi-agent)".
::
:: Requires:
::   - The NCCL-enabled llama.cpp build (built with -DGGML_CUDA_NCCL=ON against nccl-windows).
::   - nccl.dll present in %BIN_DIR% (beside llama-server.exe). Ships in the dual-card release.
::   - Both cards in TCC (or MCDM) with the NVLink bridge active (nvidia-smi nvlink --status).
::
:: Usage:
::   serve-dual-nccl.bat                         (defaults: Qwen3.6 35B, 8 parallel slots)
::   set MODEL=...gguf ^& serve-dual-nccl.bat
::   set PARALLEL=16 ^& set CTX=32768 ^& serve-dual-nccl.bat
::   set ALLREDUCE=internal ^& serve-dual-nccl.bat   (A/B vs NCCL; default nccl)
setlocal enabledelayedexpansion
cd /d "%~dp0."

if "%BIN_DIR%"=="" set BIN_DIR=%~dp0bin
if "%MODEL%"=="" set MODEL=%~dp0models\qwen3.6-35b-a3b-MTP-GGUF\Qwen3.6-35B-A3B-IQ4_XS-4.19bpw.gguf
if "%PORT%"=="" set PORT=8011
if "%CTX%"=="" set CTX=32768
if "%PARALLEL%"=="" set PARALLEL=8
if "%KV%"=="" set KV=q8_0
if "%THREADS%"=="" set THREADS=12
if "%ALLREDUCE%"=="" set ALLREDUCE=nccl

set CUDA_BIN=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin
if exist "%CUDA_BIN%\cudart64_12.dll" set PATH=%CUDA_BIN%;%PATH%
:: nccl.dll is loaded from the exe directory; make sure it's there.
if /I "%ALLREDUCE%"=="nccl" if not exist "%BIN_DIR%\nccl.dll" (
    echo nccl.dll not found in %BIN_DIR% - the NCCL all-reduce needs it.
    echo Either copy nccl.dll beside llama-server.exe, or set ALLREDUCE=internal.
    exit /b 1
)

if not exist "%MODEL%" ( echo model not found: %MODEL% & echo run download-models.bat first & exit /b 1 )

:: Select the multi-GPU all-reduce backend (nccl ^| internal ^| none). nccl = best for
:: concurrency over NVLink; internal is the Windows default (no NCCL).
set GGML_CUDA_ALLREDUCE=%ALLREDUCE%
:: Pin NCCL's bootstrap interface so it doesn't pick a VPN/Tailscale adapter. Override
:: NCCL_SOCKET_IFNAME for your box (run: nvidia-smi / ipconfig to find the LAN adapter name).
if "%NCCL_SOCKET_IFNAME%"=="" set NCCL_SOCKET_IFNAME=Ethernet

echo serving %MODEL% across 2 GPUs: -sm tensor, allreduce=%ALLREDUCE%, parallel=%PARALLEL%, ctx=%CTX%, port=%PORT%
"%BIN_DIR%\llama-server.exe" ^
  -m "%MODEL%" ^
  --host 0.0.0.0 --port %PORT% ^
  -ngl 99 -fa 1 ^
  -sm tensor -ts 1/1 ^
  -b 2048 -ub 512 ^
  -ctk %KV% -ctv %KV% ^
  -c %CTX% ^
  -t %THREADS% ^
  --parallel %PARALLEL% --cont-batching --metrics ^
  %*

endlocal
