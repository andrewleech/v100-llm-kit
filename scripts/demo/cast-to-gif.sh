#!/usr/bin/env bash
# Convert an asciinema .cast to a gif with agg, tuned for these demos.
#
# Playback is REAL-TIME (SPEED=1) on purpose — speeding it up would misrepresent how fast
# the box actually generates, which is false advertising for a product demo. The model's
# spinner animates continuously during prompt-processing and generation, so that time plays
# at true speed. --idle-time-limit only trims genuinely dead air (initial TUI draw, the pause
# after the answer before exit), which is honest. Leave SPEED at 1.
#
# Usage: ./cast-to-gif.sh <input.cast> [output.gif]

set -euo pipefail
IN="${1:?usage: cast-to-gif.sh <input.cast> [output.gif]}"
OUT="${2:-${IN%.cast}.gif}"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../assets/gifs"
mkdir -p "$OUT_DIR"
[ "$(dirname "$OUT")" = "." ] && OUT="$OUT_DIR/$(basename "$OUT")"

agg \
  --idle-time-limit "${IDLE_LIMIT:-2}" \
  --speed "${SPEED:-1}" \
  --font-size "${FONT_SIZE:-16}" \
  --theme asciinema \
  "$IN" "$OUT"

echo "wrote: $OUT" >&2
ls -lh "$OUT" >&2
