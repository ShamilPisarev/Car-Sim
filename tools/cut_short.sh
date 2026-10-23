#!/bin/sh
# Cuts the short action trailer from trailer/clips/q_*.avi (record them with tools/record_short.sh).
# Output: trailer/CarSim_trailer_30s.mp4 (+ a 720p copy for phones)
set -e
cd "$(dirname "$0")/../trailer/clips"
[ -f font.ttf ] || cp /c/Windows/Fonts/arialbd.ttf font.ttf
: > cuts.txt
n=0
cut() {  # cut clip from to "caption"
	n=$((n + 1))
	d=$(awk "BEGIN{print $3-$2}")
	fo=$(awk "BEGIN{print $3-$2-0.08}")
	txt=""
	if [ -n "$4" ]; then
		txt=",drawtext=fontfile=font.ttf:text='$4':fontsize=96:fontcolor=white:borderw=4:bordercolor=black@0.6:x=80:y=h-200:alpha='min(1,t/0.15)'"
	fi
	ffmpeg -v error -y -ss "$2" -t "$d" -i "$1.avi" \
		-vf "scale=1920:1080,fps=30,fade=in:st=0:d=0.06,fade=out:st=$fo:d=0.08$txt,format=yuv420p" \
		-af "afade=in:st=0:d=0.04,afade=out:st=$fo:d=0.08" -ar 48000 -ac 2 \
		-c:v libx264 -crf 17 -preset medium -c:a aac "cut_$n.mp4"
	echo "file 'cut_$n.mp4'" >> cuts.txt
}
card() {  # card seconds "big" "small" background_clip time
	n=$((n + 1))
	ffmpeg -v error -y -ss "$5" -i "$4.avi" -frames:v 1 "bg_$n.png"
	ffmpeg -v error -y -loop 1 -t "$1" -i "bg_$n.png" -f lavfi -t "$1" -i anullsrc=r=48000:cl=stereo \
		-vf "scale=1920:1080,boxblur=16:2,eq=brightness=-0.28,drawtext=fontfile=font.ttf:text='$2':fontsize=170:fontcolor=white:x=(w-tw)/2:y=(h-th)/2-50,drawtext=fontfile=font.ttf:text='$3':fontsize=46:fontcolor=0xFFD24D:x=(w-tw)/2:y=h/2+80,fade=in:st=0:d=0.3,fade=out:st=$(awk "BEGIN{print $1-0.3}"):d=0.3,format=yuv420p" \
		-r 30 -c:v libx264 -crf 17 -c:a aac -ar 48000 -ac 2 -shortest "cut_$n.mp4"
	echo "file 'cut_$n.mp4'" >> cuts.txt
}
card 1.6 "CAR SIM" "" q_low 13
cut q_start   6.2  8.6  ""
cut q_low    12.0 14.0  ""
cut q_cockpit 12.5 14.3 ""
cut q_flyby  17.5 19.5  ""
cut q_rain   12.0 13.8  "RAIN"
cut q_night  13.0 14.6  "NIGHT"
cut q_night  18.6 19.8  ""
cut q_cars    0.3  1.2  "4 CARS"
cut q_cars    1.7  2.6  ""
cut q_cars    3.2  4.1  ""
cut q_cars    4.8  5.8  ""
cut q_side   12.0 13.6  ""
cut q_wreck   0.6  2.8  "FULL DAMAGE"
cut q_replay 39.0 41.0  "REPLAYS"
cut q_low    21.0 22.8  ""
card 2.6 "CAR SIM" "Realistic or Arcade  -  Race  -  Championship  -  Time trial" q_replay 42
ffmpeg -v error -y -f concat -safe 0 -i cuts.txt -c:v libx264 -crf 19 -preset medium -pix_fmt yuv420p \
	-af "loudnorm=I=-15:TP=-1.5" -c:a aac -b:a 192k -movflags +faststart ../CarSim_trailer_30s.mp4
ffmpeg -v error -y -i ../CarSim_trailer_30s.mp4 -vf scale=1280:720 -c:v libx264 -crf 25 -preset slow \
	-c:a aac -b:a 128k -movflags +faststart ../CarSim_trailer_30s_720p.mp4
echo "done"
