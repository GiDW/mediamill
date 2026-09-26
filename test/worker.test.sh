#!/usr/bin/env zsh
# Worker assertions. Requires vips, vipsheader + ffmpeg on PATH (all in the image). Usage: test/worker.test.sh
set -u
zmodload zsh/stat   # zstat: portable mtime without coreutils/BSD stat differences
here="${0:A:h}"; worker="$here/../bin/mediamill-worker"
w="$(mktemp -d)"; trap 'rm -rf -- "$w"' EXIT
in="$w/in"; out="$w/out"; mkdir -p "$in/d" "$out/d"
fails=0
assert() { if eval "$2"; then print "ok   $1"; else print "FAIL $1"; fails=$((fails+1)); fi }

vips black "$in/d/a.png" 64 64
vips black "$in/d/UP.PNG" 64 64
vips black "$in/d/coll.png" 64 64
vips black "$in/d/coll.jpg" 64 64
cp "$here/fixtures/anim.gif" "$in/d/anim.gif"   # committed: the image's libvips has no GIF saver
vips black "$in/d/slash.png" 64 64
printf 'x' > "$in/d/notes.txt"
printf 'garbage' > "$in/d/broken.jpg"
# -nt compares whole seconds: make sure every first-run target is strictly newer than its source
sleep 1

export MM_IN_ROOT="$in" MM_OUT_ROOT="$out"

"$worker" "$in/d/a.png" >/dev/null;         assert "png -> jpg"              '[[ -s "$out/d/a.jpg" ]]'
assert "output is a real jpeg"               '[[ "$(vipsheader -f vips-loader "$out/d/a.jpg" 2>/dev/null)" == jpegload ]]'
assert "no temp file left"                   '[[ -z "$(ls "$out/d" | grep mmtmp)" ]]'
# EXIF Orientation=6 (rotate 90 CW) on 32x16 pixels: rotation is baked into the pixels, no metadata survives
cp "$here/fixtures/rot6.jpg" "$in/d/rot6.jpg"
"$worker" "$in/d/rot6.jpg" >/dev/null
assert "exif orientation applied (16x32)"    '[[ "$(vipsheader -f width "$out/d/rot6.jpg")x$(vipsheader -f height "$out/d/rot6.jpg")" == 16x32 ]]'
assert "exif (orientation, gps) removed"     '! grep -qa "Exif" "$out/d/rot6.jpg"'
# Display P3 red: converted to sRGB (P3 red is outside sRGB, so it clips to ~255,0,0), profile dropped
cp "$here/fixtures/p3.jpg" "$in/d/p3.jpg"
"$worker" "$in/d/p3.jpg" >/dev/null
px=(${=$(vips getpoint "$out/d/p3.jpg" 8 8)})
assert "p3 converted to srgb (red >= 250, green/blue <= 10)" '(( px[1] >= 250 && px[2] <= 10 && px[3] <= 10 ))'
assert "icc profile not embedded"            '! grep -qa "ICC_PROFILE" "$out/d/p3.jpg"'
# untagged CMYK jpeg: libvips' fallback CMYK profile turns it into 3-band sRGB (a copy kept CMYK)
vips icc_export "$here/fixtures/p3.jpg" "$w/cmyk.v" --output-profile cmyk && vips copy "$w/cmyk.v" "$in/d/cmyk.jpg[keep=none]"
"$worker" "$in/d/cmyk.jpg" >/dev/null
assert "cmyk jpeg -> 3-band srgb"            '[[ "$(vipsheader -f bands "$out/d/cmyk.jpg")" == 3 ]]'
# The mozjpeg options reach the encoder: interlace makes it progressive (SOF2 marker; entropy data
# never holds ff c2, 0xff is always byte-stuffed). The reference is progressive too, so the size
# check isolates trellis-quant/optimize-scans/quant-table/subsampling: together they save ~24% on
# this seeded noise with the same libvips; without them the sizes are equal.
vips gaussnoise "$w/n.v" 256 256 --seed 7 && vips bandjoin "$w/n.v $w/n.v $w/n.v" "$w/n3.v" && vips cast "$w/n3.v" "$in/d/noise.png" uchar
vips copy "$in/d/noise.png" "$w/plain.jpg[Q=75,keep=none,interlace]"
"$worker" "$in/d/noise.png" >/dev/null
assert "progressive jpeg (interlace)"        '[[ " $(od -An -v -tx1 "$out/d/noise.jpg" | tr -s " \n" "  ") " == *" ff c2 "* ]]'
assert "mozjpeg opts: < 90% of a plain progressive Q=75" '(( $(wc -c < "$out/d/noise.jpg") * 10 < $(wc -c < "$w/plain.jpg") * 9 ))'
"$worker" "$in/d/UP.PNG" >/dev/null;        assert "uppercase ext, stem kept" '[[ -s "$out/d/UP.jpg" ]]'
# clashes are the dispatcher's job (preflight): the worker never renames, even next to a same-stem .jpg
"$worker" "$in/d/coll.png" >/dev/null;      assert "no _2 rename in worker"   '[[ -s "$out/d/coll.jpg" && ! -e "$out/d/coll_2.jpg" ]]'
"$worker" "$in/d/notes.txt" >/dev/null;     assert "other file copied"        '[[ "$(cat "$out/d/notes.txt")" == x ]]'
"$worker" "$in/d/anim.gif" >/dev/null 2>&1; assert "gif -> mp4"               '[[ -s "$out/d/anim.mp4" ]]'
"$worker" "$in/d/broken.jpg" >/dev/null 2>"$w/err"; rc=$?
assert "broken input exits 1"                '[[ $rc -eq 1 ]]'
assert "broken input reports FAIL on stderr" 'grep -q "^FAIL d/broken.jpg" "$w/err"'
assert "broken input leaves no output"       '[[ ! -e "$out/d/broken.jpg" ]]'
mtime() { zstat +mtime -- "$1" }
# default: up-to-date target (exists, newer than source) is skipped
m1="$(mtime "$out/d/a.jpg")"; sleep 1
"$worker" "$in/d/a.png" | grep -q '^SKIP d/a.png'; rc=$?
assert "up-to-date target prints SKIP"       '[[ $rc -eq 0 ]]'
assert "up-to-date target not rewritten"     '[[ "$(mtime "$out/d/a.jpg")" == "$m1" ]]'
"$worker" "$in/d/notes.txt" | grep -q '^SKIP d/notes.txt'; rc=$?
assert "up-to-date copy also skipped"        '[[ $rc -eq 0 ]]'
# stale target (source newer than target) is rewritten
touch "$in/d/a.png"; sleep 1
"$worker" "$in/d/a.png" | grep -q '^JPG d/a.png'; rc=$?
assert "stale target rewritten, JPG line"    '[[ $rc -eq 0 && "$(mtime "$out/d/a.jpg")" != "$m1" ]]'
# --force rewrites even when up to date
m3="$(mtime "$out/d/a.jpg")"; sleep 1
MM_FORCE=1 "$worker" "$in/d/a.png" | grep -q '^JPG d/a.png'; rc=$?
assert "force rewrites up-to-date target"    '[[ $rc -eq 0 && "$(mtime "$out/d/a.jpg")" != "$m3" ]]'
# trailing slashes on the roots must not break the in -> out path mapping
MM_IN_ROOT="$in/" MM_OUT_ROOT="$out/" "$worker" "$in/d/slash.png" | grep -q '^JPG d/slash.png'; rc=$?
assert "trailing-slash roots map correctly"  '[[ $rc -eq 0 && -s "$out/d/slash.jpg" ]]'
# SIGTERM mid-conversion must leave neither the temp output nor an error file behind.
# 14000x14000 noise (stored uncompressed so generating it is cheap) takes >2 s to encode,
# so the kill at 0.3 s lands mid-conversion.
vips gaussnoise "$in/d/big.png[compression=0]" 14000 14000 >/dev/null 2>&1
( "$worker" "$in/d/big.png" >/dev/null 2>&1 & pid=$!; sleep 0.3; kill -TERM $pid; wait $pid ) 2>/dev/null
assert "killed worker leaves no temp files"  '[[ -z "$(ls "$out/d" | grep mmtmp)" && ! -e "$out/d/big.jpg" ]]'

print "failures: $fails"; exit $(( fails > 0 ))
