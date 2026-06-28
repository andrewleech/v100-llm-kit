# Serve a model across TWO V100s with NVLink, tensor-parallel + NCCL all-reduce (PowerShell).
# PowerShell equivalent of serve-dual-nccl.bat, for multi-agent / high-concurrency use.
#
# Each of PARALLEL slots gets SLOTCTX tokens (total -c = PARALLEL*SLOTCTX). Default q4_0 KV
# (measured quality-safe) so a full 262k per slot fits: 4 agents x 262k loads at ~29 GB / 32 GB.
# For more agents trade context down, e.g. $env:PARALLEL=8; $env:SLOTCTX=131072.
#
# Usage:
#   .\serve-dual-nccl.ps1                                   # 4 agents x 262k, q4_0 KV
#   $env:PARALLEL=8; $env:SLOTCTX=131072; .\serve-dual-nccl.ps1   # 8 agents x 128k
#   $env:KV='q8_0'; .\serve-dual-nccl.ps1                  # lossless KV; use smaller SLOTCTX
#   $env:ALLREDUCE='internal'; .\serve-dual-nccl.ps1       # A/B vs NCCL; default nccl
# Extra args pass straight through to llama-server.exe.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$BinDir    = if ($env:BIN_DIR)  { $env:BIN_DIR }  else { Join-Path $here 'bin' }
$Model     = if ($env:MODEL)    { $env:MODEL }    else { Join-Path $here 'models\qwen3.6-35b-a3b-MTP-GGUF\Qwen3.6-35B-A3B-IQ4_XS-4.19bpw.gguf' }
$Port      = if ($env:PORT)     { $env:PORT }     else { '8011' }
$Parallel  = if ($env:PARALLEL) { [int]$env:PARALLEL } else { 4 }
$SlotCtx   = if ($env:SLOTCTX)  { [int]$env:SLOTCTX }  else { 262144 }
$Ctx       = if ($env:CTX)      { [int]$env:CTX }      else { $Parallel * $SlotCtx }
$Kv        = if ($env:KV)       { $env:KV }       else { 'q4_0' }
$Threads   = if ($env:THREADS)  { $env:THREADS }  else { '12' }
$AllReduce = if ($env:ALLREDUCE){ $env:ALLREDUCE }else { 'nccl' }

$cuda = 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin'
if (Test-Path (Join-Path $cuda 'cudart64_12.dll')) { $env:PATH = "$cuda;$env:PATH" }
$env:PATH = "$BinDir;$env:PATH"

if ($AllReduce -eq 'nccl' -and -not (Test-Path (Join-Path $BinDir 'nccl.dll'))) {
    Write-Error "nccl.dll not found in $BinDir - the NCCL all-reduce needs it (or set `$env:ALLREDUCE='internal')."; exit 1
}
if (-not (Test-Path $Model)) { Write-Error "model not found: $Model`nrun download-models.bat first"; exit 1 }

$env:GGML_CUDA_ALLREDUCE = $AllReduce
if (-not $env:NCCL_SOCKET_IFNAME) { $env:NCCL_SOCKET_IFNAME = 'Ethernet' }

Write-Host "serving across 2 GPUs: -sm tensor allreduce=$AllReduce parallel=$Parallel slotctx=$SlotCtx ctx=$Ctx kv=$Kv port=$Port"
& (Join-Path $BinDir 'llama-server.exe') `
    -m $Model `
    --host 0.0.0.0 --port $Port `
    -ngl 99 -fa 1 `
    -sm tensor -ts 1/1 `
    -b 2048 -ub 512 `
    -ctk $Kv -ctv $Kv `
    -c $Ctx `
    -t $Threads `
    --parallel $Parallel --cont-batching --metrics `
    @args
