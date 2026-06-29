# Serve a Q6_K 35B coding model RESIDENT across both V100s on upstream llama.cpp (PowerShell).
#
# PowerShell equivalent of serve-q6-resident.bat. The production quality serve for the 35B
# coding models (Qwen3.6-35B-A3B, Ornith-1.0-35B). Q6_K (~29 GB) fits in the 32 GB across
# both cards with -sm layer -ts 1/1, so the whole model stays in VRAM (no expert offload).
# KV is cheap on this hybrid model. Decode ~80 tok/s. --kv-unified is REQUIRED for the
# cross-slot shared-prefix feature.
#
# Layout (override with env): binaries in $env:BIN_DIR (default .\bin), model in $env:MODEL.
# The CUDA 12.8 runtime is prepended to PATH so the binary finds its DLLs even if CUDA 13.x
# is also installed.
#
# Usage:
#   .\serve-q6-resident.ps1                      # 4 slots x 32k (128k total), port 8011
#   $env:CTX=65536; .\serve-q6-resident.ps1      # smaller total context
#   $env:PORT=8080; .\serve-q6-resident.ps1      # override port
#   $env:PARALLEL=8; .\serve-q6-resident.ps1     # 8 concurrent slots
#   .\serve-q6-resident.ps1 --jinja              # tool calling on (needed for Claude Code)
# Extra args pass straight through to llama-server.exe.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$BinDir   = if ($env:BIN_DIR)  { $env:BIN_DIR }  else { Join-Path $here 'bin' }
$Model    = if ($env:MODEL)    { $env:MODEL }    else { Join-Path $here 'models\qwen3.6-35b-a3b-MTP-GGUF\Qwen3.6-35B-A3B-Q6_K.gguf' }
$Port     = if ($env:PORT)     { $env:PORT }     else { '8011' }
$Parallel = if ($env:PARALLEL) { [int]$env:PARALLEL } else { 4 }
$Ctx      = if ($env:CTX)      { $env:CTX }      else { '131072' }
$Kv       = if ($env:KV)       { $env:KV }       else { 'q8_0' }

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

Write-Host "serving q6-resident ctx=$Ctx parallel=$Parallel kv=$Kv port=$Port"
& (Join-Path $BinDir 'llama-server.exe') `
    -m $Model `
    --host 0.0.0.0 --port $Port `
    -ngl 99 -fa on `
    -sm layer -ts 1/1 `
    -ctk $Kv -ctv q8_0 `
    -c $Ctx --kv-unified `
    --cont-batching --parallel $Parallel --metrics `
    @tpl @args
