#!/bin/sh
# A gameplay reel from the Simulator: builds the game, runs each scenario in
# tools/film.py's REEL with film=1 (every frame saved), cuts them together and
# encodes build/film/throwing-wood-<version>.mp4 (800 x 480, 50 fps, H.264)
# and .gif (400 x 240, 25 fps, two colours). Needs ffmpeg. About two minutes.
# sh tools/film.sh
set -e
cd "$(dirname "$0")/.."
SIM="$HOME/Developer/PlaydateSDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator"
FF=${FFMPEG:-ffmpeg}
VERSION=$(sed -n 's/^version=//p' source/pdxinfo)
OUT="$PWD/build/film"
DATA="$HOME/Developer/PlaydateSDK/Disk/Data/com.throwingwood.playdate/selftest"
make build >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"
for s in $(python3 tools/film.py --scenes); do
	rm -f "$DATA/$s.done"
	timeout -k 5 150 "$SIM" "$PWD/build/ThrowingWood.pdx" selftest="$s" out="$OUT" film=1 >/dev/null 2>&1 || true
	# The Simulator often crashes as it quits; the scenario counts only by its marker.
	if ! grep -q '^DONE' "$DATA/$s.done" 2>/dev/null; then
		echo "film: $s did not finish ($(cat "$DATA/$s.done" 2>/dev/null || echo 'no marker')); no reel" >&2
		exit 1
	fi
	echo "filmed $s: $(ls "$OUT" | grep -c "^$s-f") frames"
done
python3 tools/film.py "$OUT"
"$FF" -v error -y -framerate 50 -i "$OUT/reel/r%05d.png" \
	-vf "scale=800:480:flags=neighbor,format=yuv420p" -c:v libx264 -preset slow -crf 16 \
	-movflags +faststart "$OUT/throwing-wood-$VERSION.mp4"
"$FF" -v error -y -framerate 50 -i "$OUT/reel/r%05d.png" \
	-vf "fps=25,format=gray,split[a][b];[a]palettegen=max_colors=2:reserve_transparent=0[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
	-loop 0 "$OUT/throwing-wood-$VERSION.gif"
ls -l "$OUT"/throwing-wood-*
