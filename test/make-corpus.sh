#!/usr/bin/env zsh
# Generate a deterministic synthetic corpus. Requires vips (with heif + webp + openjpeg savers).
# Usage: test/make-corpus.sh <dir> [per-format-count]
set -eu
dir="$1"; n="${2:-5}"
rm -rf -- "$dir"
mkdir -p -- "$dir/sub one/deep" "$dir/Sub_Upper"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
vips gaussnoise "$tmp/n.v" 1800 1200 --sigma 60 --mean 128 --seed 42
vips gaussblur "$tmp/n.v" "$tmp/b.v" 4
vips bandjoin "$tmp/b.v $tmp/b.v $tmp/b.v" "$tmp/rgbf.v"
# gaussnoise yields float; jp2ksave (unlike the other savers) refuses non-integer input, so cast once here.
vips cast "$tmp/rgbf.v" "$tmp/rgb.v" uchar
for i in $(seq -w 1 "$n"); do
  vips copy "$tmp/rgb.v" "$dir/sub one/photo_$i.jpg[Q=92]"
  vips copy "$tmp/rgb.v" "$dir/sub one/deep/shot_$i.PNG"
  vips copy "$tmp/rgb.v" "$dir/Sub_Upper/pic_$i.webp[Q=90]"
  # HEIC *encoding* needs an HEVC encoder plugin; the image ships decoders only, so tolerate this in CI.
  vips copy "$tmp/rgb.v" "$dir/Sub_Upper/img_$i.heic[Q=60]" 2>/dev/null || print -u2 "warn: heic save unsupported here, skipped"
  vips copy "$tmp/rgb.v" "$dir/Sub_Upper/scan_$i.jp2"
done
vips copy "$tmp/rgb.v" "$dir/anim.gif"
# collision fixture: a non-jpg source next to a *different* file with the target name
vips copy "$tmp/rgb.v" "$dir/collide.png"
vips copy "$tmp/rgb.v" "$dir/collide.jpg[Q=50]"
printf 'not an image\n' > "$dir/readme.txt"
find "$dir" -type f | wc -l
