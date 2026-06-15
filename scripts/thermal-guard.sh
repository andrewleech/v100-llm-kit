#!/usr/bin/env bash
# Thermal guard for V100 benchmarking. Polls every GPU via nvidia-smi(.exe) and:
#   - logs each sample,
#   - prints a WARN line when any GPU core/mem crosses WARN_TEMP,
#   - on KILL_TEMP: kills the inference processes (taskkill on Windows native +
#     pkill in WSL), writes an ALARM line, and EXITS non-zero.
#
# Runs from WSL but drives the Windows-native cards via nvidia-smi.exe/taskkill.exe.
# The non-zero exit on KILL is the alarm signal — whatever launched this in the
# background gets notified that the guard tripped.
#
# Tunables (env):
#   WARN_TEMP (default 80)  KILL_TEMP (default 85)   in deg C, applies to core AND memory
#   INTERVAL  (default 3)   seconds between polls
#   LOG       (default ~/v100-thermal.log)
#   NO_KILL=1               alarm only, never kill (dry-run safety test)

set -uo pipefail

WARN_TEMP="${WARN_TEMP:-80}"
KILL_TEMP="${KILL_TEMP:-85}"
INTERVAL="${INTERVAL:-3}"
LOG="${LOG:-$HOME/v100-thermal.log}"
SMI="${SMI:-nvidia-smi.exe}"

# Resolve a working nvidia-smi (prefer the Windows one from WSL; fall back to linux).
command -v "$SMI" >/dev/null 2>&1 || SMI="nvidia-smi"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts) $*" | tee -a "$LOG"; }

kill_inference() {
  [ "${NO_KILL:-0}" = "1" ] && { log "NO_KILL set — not killing"; return; }
  # Windows-native engines
  taskkill.exe /F /IM llama-server.exe >/dev/null 2>&1 || true
  taskkill.exe /F /IM llama-bench.exe  >/dev/null 2>&1 || true
  taskkill.exe /F /IM llama-cli.exe    >/dev/null 2>&1 || true
  # WSL-side engines
  pkill -f 'llama-server' 2>/dev/null || true
  pkill -f 'llama-bench'  2>/dev/null || true
}

log "thermal-guard start: WARN=${WARN_TEMP}C KILL=${KILL_TEMP}C interval=${INTERVAL}s smi=${SMI} no_kill=${NO_KILL:-0}"

last_warn=0
while true; do
  # index, core temp, mem temp  (strip CRs from the Windows binary)
  mapfile -t rows < <("$SMI" --query-gpu=index,temperature.gpu,temperature.memory \
                        --format=csv,noheader,nounits 2>/dev/null | tr -d '\r')
  if [ "${#rows[@]}" -eq 0 ]; then
    log "WARN: nvidia-smi returned nothing"; sleep "$INTERVAL"; continue
  fi

  hot_core=0; hot_mem=0; summary=""
  for r in "${rows[@]}"; do
    IFS=',' read -r idx ct mt <<<"$r"
    idx="${idx// /}"; ct="${ct// /}"; mt="${mt// /}"
    [ -z "$ct" ] && ct=0; [ -z "$mt" ] && mt=0
    summary+="GPU${idx}:${ct}C/mem${mt}C "
    [ "$ct" -gt "$hot_core" ] && hot_core="$ct"
    [ "$mt" -gt "$hot_mem" ]  && hot_mem="$mt"
  done
  hot=$hot_core; [ "$hot_mem" -gt "$hot" ] && hot=$hot_mem

  if [ "$hot" -ge "$KILL_TEMP" ]; then
    log "ALARM: ${hot}C >= KILL ${KILL_TEMP}C [$summary] — killing inference"
    kill_inference
    log "ALARM handled — guard exiting"
    exit 1
  elif [ "$hot" -ge "$WARN_TEMP" ]; then
    now=$(date +%s)
    if [ $((now - last_warn)) -ge 15 ]; then   # rate-limit warns to ~1/15s
      log "WARN: ${hot}C >= WARN ${WARN_TEMP}C [$summary]"
      last_warn=$now
    fi
  else
    echo "$(ts) ok [$summary]" >> "$LOG"   # quiet sample, file only
  fi
  sleep "$INTERVAL"
done
