@echo off
:: Serve Qwen3.6-35B-A3B (ik_llama.cpp) on a V100, Windows native.
::
:: Layout: binaries in %BIN_DIR% (default .\bin), model in %MODEL%. CUDA 12.8 runtime is
:: prepended to PATH so the binary finds its DLLs even if CUDA 13.x is also installed.
::
:: Usage:
::   serve-qwen3.bat                 (128k context)
::   set CTX=32768 ^& serve-qwen3.bat   (smaller context, faster TG)
::   set PORT=8080 ^& serve-qwen3.bat
setlocal enabledelayedexpansion
cd /d "%~dp0."

if "%BIN_DIR%"=="" set BIN_DIR=%~dp0bin
if "%MODEL%"=="" set MODEL=%~dp0models\qwen3.6-35b-a3b-MTP-GGUF\Qwen3.6-35B-A3B-IQ4_XS-4.19bpw.gguf
if "%PORT%"=="" set PORT=8001
if "%CTX%"=="" set CTX=131072
if "%THREADS%"=="" set THREADS=12
if "%CRAM%"=="" set CRAM=16384

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

echo serving qwen3 ctx=%CTX% port=%PORT%
"%BIN_DIR%\llama-server.exe" ^
  -m "%MODEL%" ^
  --host 0.0.0.0 --port %PORT% ^
  -ngl 99 -fa on ^
  -b 2048 -ub 2048 ^
  --fit --fit-margin 1664 ^
  -ctk q8_0 -ctv q8_0 -ctkd q8_0 -ctvd q8_0 ^
  -cram %CRAM% ^
  --spec-type mtp:n_max=3,p_min=0.75 ^
  -c %CTX% ^
  --no-mmap --mlock ^
  -t %THREADS% ^
  --parallel 1 --metrics ^
  %TPL% %*

endlocal
