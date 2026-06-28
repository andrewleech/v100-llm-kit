# Measure KV-cache VRAM cost per KV quantisation, on the dual-V100 box (native Windows).
#
# Why: deciding whether q4_0 KV is worth it for fitting more / larger concurrent agents. This
# loads the dual server (serve-dual-nccl.bat) at two context sizes for each KV type, reads total
# VRAM after the model is ready, and derives KV bytes/token = dMem / dCtx. Halving KV (q8_0 ->
# q4_0) ~doubles how much context/how many --parallel agents fit. Quality is a SEPARATE check
# (see the spot-check note at the bottom) -- this script only measures the VRAM/fit side.
#
# Run from the dual-card pack folder (where serve-dual-nccl.bat + bin/ + models/ live):
#   .\bench-kv-fit.ps1
#   .\bench-kv-fit.ps1 -Kv q8_0,q4_0 -Ctx 16384,131072 -Parallel 1
#
# Needs: nvidia-smi on PATH, the dual server's deps (nccl.dll etc.), and the model present.
# It starts and stops llama-server.exe itself; nothing else should be using the GPUs meanwhile.
#
# If the automation misbehaves, do it by hand instead: in one terminal
#   set KV=q4_0 & set CTX=131072 & set PARALLEL=1 & serve-dual-nccl.bat
# wait for "server is listening", then in another:  nvidia-smi --query-gpu=memory.used --format=csv
# Repeat for each (KV, CTX) and subtract.
param(
    [string[]]$Kv       = @('q8_0','q4_0'),
    [int[]]   $Ctx      = @(16384, 131072),
    [int]     $Parallel = 1,
    [int]     $Port     = 8011,
    [int]     $ReadyTimeoutSec = 240
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bat  = Join-Path $here 'serve-dual-nccl.bat'
if (-not (Test-Path $bat)) { Write-Error "serve-dual-nccl.bat not found next to this script"; exit 1 }

function Get-VramUsedMB {
    # Sum memory.used across all GPUs (MiB).
    $vals = & nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits
    ($vals | ForEach-Object { [int]($_.Trim()) } | Measure-Object -Sum).Sum
}

function Stop-Server {
    Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # wait for it to actually exit / free VRAM
    for ($i = 0; $i -lt 30 -and (Get-Process llama-server -ErrorAction SilentlyContinue); $i++) { Start-Sleep 1 }
    Start-Sleep 2
}

$rows = @()
try {
    foreach ($k in $Kv) {
        foreach ($c in $Ctx) {
            Stop-Server
            $env:KV = $k; $env:CTX = "$c"; $env:PARALLEL = "$Parallel"; $env:PORT = "$Port"
            Write-Host "`n=== KV=$k CTX=$c PARALLEL=$Parallel ===" -ForegroundColor Cyan
            $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$bat`"" -PassThru -WindowStyle Minimized

            # wait for /health to report ready
            $ready = $false
            for ($t = 0; $t -lt $ReadyTimeoutSec; $t++) {
                if ($proc.HasExited) { break }
                try {
                    $r = Invoke-WebRequest -Uri "http://localhost:$Port/health" -UseBasicParsing -TimeoutSec 2
                    if ($r.StatusCode -eq 200) { $ready = $true; break }
                } catch { }
                Start-Sleep 1
            }
            if (-not $ready) {
                Write-Warning "server did not become ready for KV=$k CTX=$c (timeout/exit); skipping"
                Stop-Server
                continue
            }
            Start-Sleep 3   # let allocations settle
            $mb = Get-VramUsedMB
            Write-Host ("ready. total VRAM used = {0} MiB" -f $mb) -ForegroundColor Green
            $rows += [pscustomobject]@{ KV = $k; Ctx = $c; VramMiB = $mb }
            Stop-Server
        }
    }
} finally {
    Stop-Server
    $env:KV = $null; $env:CTX = $null; $env:PARALLEL = $null; $env:PORT = $null
}

Write-Host "`n==================== RESULTS ====================" -ForegroundColor Yellow
$rows | Format-Table -AutoSize

# KV bytes/token per type, from the delta between the two largest/smallest contexts measured.
foreach ($k in ($rows.KV | Select-Object -Unique)) {
    $r = $rows | Where-Object KV -eq $k | Sort-Object Ctx
    if ($r.Count -ge 2) {
        $lo = $r[0]; $hi = $r[-1]
        $bytesPerTok = (($hi.VramMiB - $lo.VramMiB) * 1MB) / ($hi.Ctx - $lo.Ctx)
        "{0,-6}: ~{1:N0} bytes/token  (from {2}->{3} ctx, {4}->{5} MiB)" -f `
            $k, $bytesPerTok, $lo.Ctx, $hi.Ctx, $lo.VramMiB, $hi.VramMiB
    }
}
Write-Host @"

Interpretation:
  - bytes/token x target_context = KV VRAM for one agent at that context.
  - (32GB total - ~18GB weights - compute buffers) / KV-per-agent ~= concurrent agents that fit.
  - If q4_0 ~halves bytes/token vs q8_0 with acceptable quality, you ~double agents/context.

Quality spot-check (do this separately, q4_0 is lossy):
  Serve with KV=q4_0, then run the same 2-3 real coding tasks you'd give a subagent through
  Claude Code (./claude-code.ps1) and compare against KV=q8_0. Watch long-context recall and
  tool-call/JSON correctness, that's where low-bit KV degrades first.
"@
