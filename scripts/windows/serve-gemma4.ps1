# Serve Gemma 4 26B-A4B QAT (upstream llama.cpp) on a V100, Windows native (PowerShell).
#
# PowerShell equivalent of serve-gemma4.bat. Fits entirely in 16 GB VRAM, no CPU offload.
# The CUDA 12.8 runtime is prepended to PATH so the binary finds its DLLs even if CUDA 13.x
# is also installed. Layout (override with env): binaries in $env:BIN_DIR, model in $env:MODEL.
#
# Usage:
#   .\serve-gemma4.ps1                      # 32k context, port 8011
#   $env:CTX=131072; .\serve-gemma4.ps1     # 128k
#   $env:PORT=8080; .\serve-gemma4.ps1      # override port
#   .\serve-gemma4.ps1 --jinja              # tool calling on (needed for Claude Code)
# Extra args pass straight through to llama-server.exe.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$BinDir  = if ($env:BIN_DIR) { $env:BIN_DIR } else { Join-Path $here 'bin' }
$Model   = if ($env:MODEL)   { $env:MODEL }   else { Join-Path $here 'models\gemma-4-26B-A4B-qat\gemma-4-26B_q4_0-it.gguf' }
$Port    = if ($env:PORT)    { $env:PORT }    else { '8011' }
$Ctx     = if ($env:CTX)     { $env:CTX }     else { '32768' }
$Threads = if ($env:THREADS) { $env:THREADS } else { '6' }

$cudaBin = 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin'
if (Test-Path (Join-Path $cudaBin 'cudart64_12.dll')) { $env:PATH = "$cudaBin;$env:PATH" }

if (-not (Test-Path $Model)) {
    Write-Error "model not found: $Model`nrun download-models.bat first"
    exit 1
}

# With --jinja (tool calling), default to the bundled no-think template (thinking adds latency
# for agentic use). Skipped if you passed --chat-template-file, or set $env:THINK=1 for thinking-on.
$tpl = @()
$hasJinja = $args -contains '--jinja'
$hasTpl   = $args -contains '--chat-template-file'
if ($hasJinja -and -not $hasTpl -and $env:THINK -ne '1') {
    $tpl = @('--chat-template-file', (Join-Path $here 'gemma4-template-nothink.jinja'))
}

Write-Host "serving gemma4 ctx=$Ctx port=$Port"
& (Join-Path $BinDir 'llama-server.exe') `
    -m $Model `
    --host 0.0.0.0 --port $Port `
    -ngl 99 -fa 1 `
    -b 2048 -ub 1024 `
    -ctk q8_0 -ctv q8_0 `
    -c $Ctx `
    -t $Threads `
    --parallel 1 --metrics `
    @tpl @args
