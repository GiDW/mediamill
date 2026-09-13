#!/usr/bin/env zsh
# Worker assertions. Requires vips + ffmpeg on PATH. Usage: test/worker.test.sh
set -u
here="${0:A:h}"; worker="$here/../bin/mediamill-worker"
w="$(mktemp -d)"; trap 'rm -rf -- "$w"' EXIT
in="$w/in"; out="$w/out"; mkdir -p "$in/d" "$out/d"
fails=0
assert() { if eval "$2"; then print "ok   $1"; else print "FAIL $1"; fails=$((fails+1)); fi }

vips black "$in/d/a.png" 64 64
vips black "$in/d/UP.PNG" 64 64
vips black "$in/d/coll.png" 64 64
vips black "$in/d/coll.jpg" 64 64
vips black "$in/d/anim.gif" 64 64
printf 'x' > "$in/d/notes.txt"
printf 'garbage' > "$in/d/broken.jpg"
# -nt compares whole seconds: make sure every first-run target is strictly newer than its source
sleep 1

export MM_IN_ROOT="$in" MM_OUT_ROOT="$out"

"$worker" "$in/d/a.png" >/dev/null;         assert "png -> jpg"              '[[ -s "$out/d/a.jpg" ]]'
assert "output is a real jpeg"               '[[ "$(vipsheader -f vips-loader "$out/d/a.jpg" 2>/dev/null)" == jpegload ]]'
assert "no temp file left"                   '[[ -z "$(ls "$out/d" | grep mmtmp)" ]]'
"$worker" "$in/d/UP.PNG" >/dev/null;        assert "uppercase ext, stem kept" '[[ -s "$out/d/UP.jpg" ]]'
"$worker" "$in/d/coll.png" >/dev/null;      assert "collision -> _2"          '[[ -s "$out/d/coll_2.jpg" ]]'
"$worker" "$in/d/coll.jpg" >/dev/null;      assert "jpg source keeps name"    '[[ -s "$out/d/coll.jpg" ]]'
"$worker" "$in/d/notes.txt" >/dev/null;     assert "other file copied"        '[[ "$(cat "$out/d/notes.txt")" == x ]]'
"$worker" "$in/d/anim.gif" >/dev/null 2>&1; assert "gif -> mp4"               '[[ -s "$out/d/anim.mp4" ]]'
"$worker" "$in/d/broken.jpg" >/dev/null 2>"$w/err"; rc=$?
assert "broken input exits 1"                '[[ $rc -eq 1 ]]'
assert "broken input reports FAIL on stderr" 'grep -q "^FAIL d/broken.jpg" "$w/err"'
assert "broken input leaves no output"       '[[ ! -e "$out/d/broken.jpg" ]]'
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" }
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
# SIGTERM mid-conversion must leave neither the temp output nor an error file behind.
# 14000x14000 noise (stored uncompressed so generating it is cheap) takes >2 s to encode,
# so the kill at 0.3 s lands mid-conversion.
vips gaussnoise "$in/d/big.png[compression=0]" 14000 14000 >/dev/null 2>&1
( "$worker" "$in/d/big.png" >/dev/null 2>&1 & pid=$!; sleep 0.3; kill -TERM $pid; wait $pid ) 2>/dev/null
assert "killed worker leaves no temp files"  '[[ -z "$(ls "$out/d" | grep mmtmp)" && ! -e "$out/d/big.jpg" ]]'

print "failures: $fails"; exit $(( fails > 0 ))
