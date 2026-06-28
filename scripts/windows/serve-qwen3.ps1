# Serve Qwen3.6-35B-A3B (ik_llama.cpp) on a V100, Windows native (PowerShell).
#
# PowerShell equivalent of serve-qwen3.bat. The server always runs natively on Windows;
# this is just a launcher. Layout (override with env): binaries in $env:BIN_DIR (default
# .\bin), model in $env:MODEL. The CUDA 12.8 runtime is prepended to PATH so the binary
# finds its DLLs even if CUDA 13.x is also installed.
#
# Usage:
#   .\serve-qwen3.ps1                       # 128k context, port 8001
#   $env:CTX=32768; .\serve-qwen3.ps1       # smaller context, faster TG
#   $env:PORT=8080; .\serve-qwen3.ps1       # override port
#   .\serve-qwen3.ps1 --jinja               # tool calling on (needed for Claude Code)
# Extra args pass straight through to llama-server.exe.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$BinDir  = if ($env:BIN_DIR) { $env:BIN_DIR } else { Join-Path $here 'bin' }
$Model   = if ($env:MODEL)   { $env:MODEL }   else { Join-Path $here 'models\qwen3.6-35b-a3b-MTP-GGUF\Qwen3.6-35B-A3B-IQ4_XS-4.19bpw.gguf' }
$Port    = if ($env:PORT)    { $env:PORT }    else { '8001' }
$Ctx     = if ($env:CTX)     { $env:CTX }     else { '131072' }
$Threads = if ($env:THREADS) { $env:THREADS } else { '12' }
$Cram    = if ($env:CRAM)    { $env:CRAM }    else { '16384' }
$Kv      = if ($env:KV)      { $env:KV }      else { 'q8_0' }

$cudaBin = 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin'
if (Test-Path (Join-Path $cudaBin 'cudart64_12.dll')) { $env:PATH = "$cudaBin;$env:PATH" }

if (-not (Test-Path $Model)) {
    Write-Error "model not found: $Model`nrun download-models.bat first"
    exit 1
}

# With --jinja (tool calling), default to the bundled no-think template (thinking adds latency
# for agentic use; the no-think template also carries the system-message fix Claude Code needs).
# Skipped if you passed --chat-template-file, or set $env:THINK=1 for thinking-on.
$tpl = @()
$hasJinja = $args -contains '--jinja'
$hasTpl   = $args -contains '--chat-template-file'
if ($hasJinja -and -not $hasTpl -and $env:THINK -ne '1') {
    $tpl = @('--chat-template-file', (Join-Path $here 'qwen3-template-nothink.jinja'))
}

Write-Host "serving qwen3 ctx=$Ctx port=$Port"
& (Join-Path $BinDir 'llama-server.exe') `
    -m $Model `
    --host 0.0.0.0 --port $Port `
    -ngl 99 -fa on `
    -b 2048 -ub 2048 `
    --fit --fit-margin 1664 `
    -ctk $Kv -ctv $Kv -ctkd $Kv -ctvd $Kv `
    -cram $Cram `
    --spec-type mtp:n_max=3,p_min=0.75 `
    -c $Ctx `
    --no-mmap --mlock `
    -t $Threads `
    --parallel 1 --metrics `
    @tpl @args
