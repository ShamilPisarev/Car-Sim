#!/bin/sh
# Records the scenes for the short action trailer (trailer/clips/q_*.avi). Cut with tools/cut_short.sh.
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"
G="${GODOT:-$LOCALAPPDATA/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe}"
OUT="$ROOT/trailer/clips"
mkdir -p "$OUT"
printf '[display]\n\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\n' > godot/override.cfg
trap 'rm -f "$ROOT/godot/override.cfg"' EXIT
rec() {  # rec clip "flags"
	echo "recording $1"
	(cd godot && "$G" --fixed-fps 30 --write-movie "$OUT/$1.avi" --path . -- --selftest=trailer --clip=$1 $2 > "$OUT/$1.log" 2>&1) || true
}
for spec in "q_start --car=midship" "q_low --car=longhood --sunset" "q_flyby --car=gt" "q_side --car=fastback --sunset" \
	"q_cockpit --car=midship" "q_rain --car=fastback --rain" "q_night --car=gt --night" "q_wreck --car=gt" \
	"q_drift --car=longhood" "q_replay --car=midship --sunset" "q_cars"; do
	set -- $spec
	c=$1; shift
	if [ -n "$ONLY" ] && [ "$ONLY" != "$c" ]; then continue; fi
	rec "$c" "$*"
done
echo "recorded"
