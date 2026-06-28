@echo off
:: Serve Gemma 4 26B-A4B QAT (upstream llama.cpp) on a V100, Windows native.
::
:: Fits entirely in 16 GB VRAM, no CPU offload. CUDA 12.8 runtime prepended to PATH.
::
:: Usage:
::   serve-gemma4.bat                (32k context)
::   set CTX=131072 ^& serve-gemma4.bat   (128k)
::   set PORT=8011 ^& serve-gemma4.bat
setlocal enabledelayedexpansion
cd /d "%~dp0."

if "%BIN_DIR%"=="" set BIN_DIR=%~dp0bin
if "%MODEL%"=="" set MODEL=%~dp0models\gemma-4-26B-A4B-qat\gemma-4-26B_q4_0-it.gguf
if "%PORT%"=="" set PORT=8011
if "%CTX%"=="" set CTX=32768
if "%KV%"=="" set KV=q8_0
if "%THREADS%"=="" set THREADS=6

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
if "%HASJINJA%"=="1" if not "%HASTPL%"=="1" if not "%THINK%"=="1" set TPL=--chat-template-file "%~dp0gemma4-template-nothink.jinja"

echo serving gemma4 ctx=%CTX% port=%PORT%
"%BIN_DIR%\llama-server.exe" ^
  -m "%MODEL%" ^
  --host 0.0.0.0 --port %PORT% ^
  -ngl 99 -fa 1 ^
  -b 2048 -ub 1024 ^
  -ctk %KV% -ctv %KV% ^
  -c %CTX% ^
  -t %THREADS% ^
  --parallel 1 --metrics ^
  %TPL% %*

endlocal
