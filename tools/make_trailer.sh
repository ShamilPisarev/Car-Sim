#!/bin/sh
# Records the trailer scenes with Godot's Movie Maker and cuts them together with ffmpeg.
# Output: trailer/CarSim_trailer.mp4
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"
G="${GODOT:-$LOCALAPPDATA/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe}"
OUT="$ROOT/trailer/clips"
mkdir -p "$OUT"
# 1080p recording without touching the project settings
printf '[display]\n\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\n' > godot/override.cfg
trap 'rm -f "$ROOT/godot/override.cfg"' EXIT

rec() {  # rec clip "flags" keep_from keep_to
	echo "recording $1"
	(cd godot && "$G" --fixed-fps 30 --write-movie "$OUT/$1.avi" --path . -- --selftest=trailer --clip=$1 $2 > "$OUT/$1.log" 2>&1) || true
	ffmpeg -v error -y -ss "$3" -to "$4" -i "$OUT/$1.avi" \
		-vf "fade=in:st=0:d=0.3,fade=out:st=$(awk "BEGIN{print $4-$3-0.35}"):d=0.35,format=yuv420p" \
		-af "afade=in:st=0:d=0.3,afade=out:st=$(awk "BEGIN{print $4-$3-0.35}"):d=0.35" \
		-c:v libx264 -crf 18 -preset medium -r 30 -c:a aac -ar 48000 -ac 2 "$OUT/$1.mp4"
}
rec start   ""          3.0 15.0
rec cars    ""          0.3 12.4
rec pack    "--sunset" 22.0 31.0
rec cockpit ""         14.0 21.0
rec drift   ""          5.5 12.0
rec rain    "--rain"   20.0 28.0
rec night   "--night"  24.0 33.0
rec crash   ""          0.0  6.5
rec replay  "--sunset" 40.0 48.0

card() {  # card name seconds "big" "small" background_clip
	cd "$OUT"
	ffmpeg -v error -y -ss 4 -i "$5.mp4" -frames:v 1 bg_$1.png
	ffmpeg -v error -y -loop 1 -t "$2" -i bg_$1.png -f lavfi -t "$2" -i anullsrc=r=48000:cl=stereo \
		-vf "boxblur=18:2,eq=brightness=-0.25,drawtext=fontfile=font.ttf:text='$3':fontsize=150:fontcolor=white:x=(w-tw)/2:y=(h-th)/2-60,drawtext=fontfile=font.ttf:text='$4':fontsize=48:fontcolor=0xFFD24D:x=(w-tw)/2:y=(h/2)+70,fade=in:st=0:d=0.5,fade=out:st=$(awk "BEGIN{print $2-0.5}"):d=0.5,format=yuv420p" \
		-c:v libx264 -crf 18 -r 30 -c:a aac -ar 48000 -ac 2 -shortest $1.mp4
	cd "$ROOT"
}
card title 3.5 "CAR SIM" "GT racing - built with Godot and Blender" pack
card end 4.0 "CAR SIM" "Realistic or Arcade - Race - Championship - Time trial" night

cd "$OUT"
: > list.txt
for c in title start cars pack cockpit drift rain night crash replay end; do echo "file '$c.mp4'" >> list.txt; done
ffmpeg -v error -y -f concat -safe 0 -i list.txt -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p \
	-af "loudnorm=I=-16:TP=-1.5" -c:a aac -b:a 192k -movflags +faststart "$ROOT/trailer/CarSim_trailer.mp4"
echo "done: $ROOT/trailer/CarSim_trailer.mp4"
