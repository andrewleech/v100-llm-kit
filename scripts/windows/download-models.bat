@echo off
:: Pull the GGUF models into .\models. Needs a free Hugging Face account + token
:: (https://huggingface.co/settings/tokens) and the hf CLI:
::   pip install -U "huggingface_hub[hf_transfer]"
::
:: Usage:
::   download-models.bat            (both models)
::   download-models.bat gemma      (just Gemma 4)
::   download-models.bat qwen       (just Qwen3)
::
:: Models must live on a Windows NTFS drive. Never point the Windows binary at \\wsl$\...
setlocal enabledelayedexpansion
cd /d "%~dp0."

if "%MODEL_DIR%"=="" set MODEL_DIR=%~dp0models
set WHICH=%1
if "%WHICH%"=="" set WHICH=all

where hf >nul 2>nul
if errorlevel 1 (
    echo hf CLI not found. Install with: pip install -U "huggingface_hub[hf_transfer]"
    exit /b 1
)
set HF_HUB_ENABLE_HF_TRANSFER=1

if /i "%WHICH%"=="gemma" goto gemma
if /i "%WHICH%"=="qwen"  goto qwen
if /i "%WHICH%"=="all"   goto all
echo usage: %~nx0 [gemma^|qwen^|all]
exit /b 1

:gemma
echo ^>^> Gemma 4 26B-A4B QAT Q4_0 (~13.4 GB)
hf download google/gemma-4-26B-A4B-it-qat-q4_0-gguf gemma-4-26B_q4_0-it.gguf --local-dir "%MODEL_DIR%\gemma-4-26B-A4B-qat"
goto done

:qwen
echo ^>^> Qwen3.6 35B-A3B IQ4_XS (~18.6 GB)
hf download byteshape/Qwen3.6-35B-A3B-MTP-GGUF Qwen3.6-35B-A3B-IQ4_XS-4.19bpw.gguf --local-dir "%MODEL_DIR%\qwen3.6-35b-a3b-MTP-GGUF"
goto done

:all
call :gemma
call :qwen

:done
echo done. models in %MODEL_DIR%
endlocal
