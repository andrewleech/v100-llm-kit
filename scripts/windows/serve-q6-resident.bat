@echo off
:: Serve a Q6_K 35B coding model RESIDENT across both V100s on upstream llama.cpp, Windows native.
::
:: The production quality serve for the 35B coding models (Qwen3.6-35B-A3B, Ornith-1.0-35B).
:: Q6_K (~29 GB) fits in the 32 GB across both cards with -sm layer -ts 1/1, so the whole model
:: stays in VRAM (no expert offload to CPU RAM). KV is cheap on this hybrid model, so a big shared
:: pool is affordable. Decode ~80 tok/s. --kv-unified is REQUIRED for the cross-slot shared-prefix
:: feature.
::
:: Layout: binaries in %BIN_DIR% (default .\bin), model in %MODEL%. CUDA 12.8 runtime is
:: prepended to PATH so the binary finds its DLLs even if CUDA 13.x is also installed.
::
:: Usage:
::   serve-q6-resident.bat                        (4 slots x 32k = 128k total, port 8011)
::   set CTX=65536 ^& serve-q6-resident.bat          (smaller total context)
::   set PORT=8080 ^& serve-q6-resident.bat
::   set PARALLEL=8 ^& serve-q6-resident.bat         (8 concurrent slots)
setlocal enabledelayedexpansion
cd /d "%~dp0."

if "%BIN_DIR%"=="" set BIN_DIR=%~dp0bin
if "%MODEL%"=="" set MODEL=%~dp0models\qwen3.6-35b-a3b-MTP-GGUF\Qwen3.6-35B-A3B-Q6_K.gguf
if "%PORT%"=="" set PORT=8011
if "%PARALLEL%"=="" set PARALLEL=4
if "%CTX%"=="" set CTX=131072
if "%KV%"=="" set KV=q8_0

set CUDA_BIN=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin
if exist "%CUDA_BIN%\cudart64_12.dll" set PATH=%CUDA_BIN%;%PATH%

if not exist "%MODEL%" (
    echo model not found: %MODEL%
    echo run download-models.bat first
    exit /b 1
)

:: With --jinja (tool calling), default to the bundled no-think template (thinking adds latency
:: for agentic use). Skipped if you passed --chat-template-file, or set THINK=1 for thinking-on.
set TPL=
set HASJINJA=
set HASTPL=
echo %* | findstr /C:"--jinja" >nul && set HASJINJA=1
echo %* | findstr /C:"--chat-template-file" >nul && set HASTPL=1
if "%HASJINJA%"=="1" if not "%HASTPL%"=="1" if not "%THINK%"=="1" set TPL=--chat-template-file "%~dp0qwen3-template-nothink.jinja"

echo serving q6-resident ctx=%CTX% parallel=%PARALLEL% kv=%KV% port=%PORT%
"%BIN_DIR%\llama-server.exe" ^
  -m "%MODEL%" ^
  --host 0.0.0.0 --port %PORT% ^
  -ngl 99 -fa on ^
  -sm layer -ts 1/1 ^
  -ctk %KV% -ctv q8_0 ^
  -c %CTX% --kv-unified ^
  --cont-batching --parallel %PARALLEL% --metrics ^
  %TPL% %*

endlocal
