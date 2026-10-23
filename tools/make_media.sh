#!/bin/sh
# Turns the frames from game/art/media_capture.gd into docs/media GIFs, and crops the banner and
# the social preview out of docs/media/title-scene.png. Needs ffmpeg on PATH (or FFMPEG=...).
#   tools/make_media.sh FRAMES_DIR     (FRAMES_DIR/drive, /putt, /flyover from the capture runs)
set -e
FFMPEG=${FFMPEG:-ffmpeg}
FRAMES=$1
MEDIA=$(dirname "$0")/../docs/media

# gif NAME WIDTH FPS [FIRST_FRAME]: two-pass palette, Bayer dither (small and steady between frames)
gif() {
	"$FFMPEG" -v error -y -framerate 30 -start_number "${4:-0}" -i "$FRAMES/$1/%04d.jpg" \
		-vf "fps=$3,scale=$2:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
		"$MEDIA/$1.gif"
	echo "$MEDIA/$1.gif $(du -k "$MEDIA/$1.gif" | cut -f1) KB"
}

if [ -n "$FRAMES" ]; then
	gif drive "${DRIVE_WIDTH:-640}" 15
	gif putt "${PUTT_WIDTH:-640}" 15
	gif flyover "${FLYOVER_WIDTH:-560}" 12 4 # (from the fade-in)
fi

# Banner 1280x400 from the title scene; social preview 1280x640: the banner over a strip of the
# parkland course from the tee
"$FFMPEG" -v error -y -i "$MEDIA/title-scene.png" -vf "crop=1920:600:0:90,scale=1280:400:flags=lanczos" "$MEDIA/banner.png"
"$FFMPEG" -v error -y -i "$MEDIA/banner.png" -i "$MEDIA/biome-parkland.png" -filter_complex "[1]scale=1280:720:flags=lanczos,crop=1280:240:0:250[c];[0][c]vstack" "$MEDIA/social-preview.png"
echo "$MEDIA/banner.png $MEDIA/social-preview.png"

# Biome thumbnails for the README's row (320x180 JPEG)
mkdir -p "$MEDIA/thumbs"
for f in "$MEDIA"/biome-*.png; do
	"$FFMPEG" -v error -y -i "$f" -vf "scale=320:180:flags=lanczos" -q:v 3 "$MEDIA/thumbs/$(basename "$f" .png).jpg"
done
echo "$MEDIA/thumbs/"
