#!/bin/bash
# App Preview для Mac App Store из записи экрана (⌘⇧5, весь экран).
#   make-preview.sh <запись.mov> [начало, с] [конец, с] [ускорение]
# Обрезает меню и правый край с виджетами, приводит к 1920×1080, 30 fps,
# H.264, добавляет тихую стерео-дорожку (App Store её ждёт) и проверяет
# длительность 15–30 с. Результат — out/preview.mp4.
set -euo pipefail
in=$1; start=${2:-0}; end=${3:-}; speed=${4:-1}
here=$(cd "$(dirname "$0")" && pwd)
out="$here/out/preview.mp4"
mkdir -p "$here/out"

# Запись Retina-экрана 3600×2338: без строки меню (сверху) и без виджетов
# стола справа — область 16:9 под карточками.
crop="crop=iw*0.875:iw*0.875*9/16:iw*0.0167:ih*0.034"
trim=(-ss "$start"); [ -n "$end" ] && trim+=(-to "$end")

ffmpeg -y -loglevel error "${trim[@]}" -i "$in" \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
  -filter_complex "[0:v]$crop,setpts=PTS/$speed,scale=1920:1080:flags=lanczos,fps=30,format=yuv420p[v]" \
  -map "[v]" -map 1:a -shortest \
  -c:v libx264 -profile:v high -preset slow -crf 18 -c:a aac -b:a 256k \
  -movflags +faststart "$out"

d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out")
echo "$out — ${d%.*} с"
awk -v d="$d" 'BEGIN { if (d < 15 || d > 30) { print "App Store принимает 15–30 с — подрежьте начало/конец или поменяйте ускорение"; exit 1 } }'
