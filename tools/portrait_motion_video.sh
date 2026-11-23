#!/usr/bin/env bash
# Enregistre la démonstration des portraits animés (tools/portrait_motion_demo.gd) en vidéo MP4.
#   tools/portrait_motion_video.sh [sortie.mp4] [secondes]
# Demande xvfb-run, godot (variable GODOT) et ffmpeg.
set -eu
cd "$(dirname "$0")/.."
OUT="${1:-portraits-animes.mp4}"
SECS="${2:-12}"
GODOT="${GODOT:-godot}"
TMP="$(mktemp -d)"
CAPTURE_DIR="$TMP" SECONDS="$SECS" xvfb-run -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver opengl3 \
	--resolution 1280x720 --fixed-fps 30 --path . -s res://tools/portrait_motion_demo.gd > "$TMP/godot.log" 2>&1
ffmpeg -y -loglevel error -framerate 30 -i "$TMP/f_%04d.png" -c:v libx264 -pix_fmt yuv420p -crf 18 "$OUT"
rm -rf "$TMP"
echo "$OUT"
