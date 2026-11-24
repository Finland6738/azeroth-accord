#!/usr/bin/env bash
# Renders every mockup page of html/ to img/ (annotated, with the numbered callouts and the legend) and img/clean/ (without
# them) with headless Chrome or Edge, then converts the PNGs to WebP (optimize_images.py).
# Adapted from Azeroth Guild Finder (docs/specs/mockups/render.sh), same owner, GPL-3.0 (ADR 0018).
# The pages are written by `python -X utf8 tools/make_mockups.py --spec` (they share the scenes of the design previews).
# Usage: bash docs/specs/mockups/render.sh [name-filter]      (CHROME=<path to chrome or msedge> overrides the search)
set -euo pipefail
cd "$(dirname "$0")"
if [ -z "${CHROME:-}" ]; then
  for c in "/c/Program Files/Google/Chrome/Application/chrome.exe" "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
           "/c/Program Files/Microsoft/Edge/Application/msedge.exe" /usr/bin/google-chrome /usr/bin/chromium /usr/bin/chromium-browser; do
    if [ -x "$c" ]; then CHROME="$c"; break; fi
  done
fi
: "${CHROME:?No Chrome or Edge found: set the CHROME environment variable to its path}"
mkdir -p img/clean
topath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }
for f in html/*${1:-}*.html; do
  name="$(basename "$f" .html)"
  url="file:///$(topath "$PWD/$f")"
  for mode in annotated clean; do
    if [ "$mode" = clean ]; then out="img/clean/$name.png"; q="?clean"; else out="img/$name.png"; q=""; fi
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --allow-file-access-from-files --window-size=1200,754 \
      --virtual-time-budget=3000 --screenshot="$(topath "$PWD/$out")" "$url$q" >/dev/null 2>&1
    echo "rendered $out"
  done
done
python optimize_images.py img 2>/dev/null && echo "converted to webp in img/" || echo "Pillow not found: PNGs left as they are"
