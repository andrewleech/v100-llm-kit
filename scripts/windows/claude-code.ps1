# Launch Claude Code against the local V100 server (native Windows, PowerShell).
#
# The server must already be running (serve-qwen3.ps1 / serve-gemma4.ps1, started with --jinja).
# This wrapper sets the ANTHROPIC_* env vars and runs `claude`. The model name matters: Claude
# Code injects it into the system prompt, so it's what the model reports when asked what it is.
#
# Usage:
#   .\claude-code.ps1                            # Qwen3 (suggested), port 8001
#   .\claude-code.ps1 -Gemma                     # Gemma 4 (faster, simple tasks), port 8011
#   .\claude-code.ps1 -p "what model are you?"   # extra args pass through to claude
#   $env:HOST="1.2.3.4"; .\claude-code.ps1       # server on another host
$ErrorActionPreference = 'Stop'

# Manual arg scan (no param block) so claude's own flags (-p, --continue, ...) pass through clean.
$gemma = $false
$rest = @()
foreach ($a in $args) {
    if ($a -eq '-Gemma' -or $a -eq '--gemma' -or $a -eq '-g') { $gemma = $true }
    else { $rest += $a }
}

if ($gemma) {
    $model = 'Gemma-4-26B-A4B'
    $port  = if ($env:PORT) { $env:PORT } else { '8011' }
} else {
    $model = 'Qwen3.6-35B-A3B'
    $port  = if ($env:PORT) { $env:PORT } else { '8001' }
}
$serverHost = if ($env:HOST) { $env:HOST } else { 'localhost' }

$env:ANTHROPIC_BASE_URL = "http://${serverHost}:${port}"
$env:ANTHROPIC_API_KEY  = 'sk-local'   # ignored by the local server
$env:ANTHROPIC_MODEL = $model
$env:ANTHROPIC_SMALL_FAST_MODEL = $model
$env:ANTHROPIC_DEFAULT_OPUS_MODEL = $model
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $model
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $model

Write-Host "Claude Code -> $($env:ANTHROPIC_BASE_URL)  model=$model"
& claude @rest
