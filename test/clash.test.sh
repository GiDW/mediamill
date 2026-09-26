#!/usr/bin/env zsh
# Clash preflight of libexec/mediamill (directory mode). vips/ffmpeg are stubbed with cp:
# this tests naming, not encoding, so it needs no media tools. Usage: test/clash.test.sh
set -u
here="${0:A:h}"; mm="$here/../libexec/mediamill"
w="$(mktemp -d)"; trap 'rm -rf -- "$w"' EXIT
fails=0
assert() { if eval "$2"; then print "ok   $1"; else print "FAIL $1"; fails=$((fails+1)); fi }

mkdir -p "$w/stub"
print -r -- '#!/bin/sh
cp -- "$2" "${3%%\[*}"' > "$w/stub/vips"                       # vips <op> <in> <out>[opts] ...
print -r -- '#!/bin/sh
while [ "$1" != -i ]; do shift; done; in="$2"
for a; do out="$a"; done; cp -- "$in" "$out"' > "$w/stub/ffmpeg"  # ... -i <in> ... <out>
chmod +x "$w/stub/vips" "$w/stub/ffmpeg"
export MM_VIPS="$w/stub/vips" MM_FFMPEG="$w/stub/ffmpeg"

# run <case>: converts $w/<case>/in into $w/<case>/out; rc in $rc, stderr in $w/<case>/err
run() { "$mm" --jobs 2 "$w/$1/in" "$w/$1/out" >"$w/$1/log" 2>"$w/$1/err"; rc=$? }
mk() { local c="$1"; shift; local f; for f; do mkdir -p -- "$w/$c/in/${f:h}"; print -r -- "$f" > "$w/$c/in/$f"; done }

mk ext IMG_0001.jpeg IMG_0001.png
run ext
assert "jpeg + png: exit 3"                    '[[ $rc -eq 3 ]]'
assert "jpeg + png: CLASH line names both"     'grep -qxF "CLASH IMG_0001.jpg <- IMG_0001.jpeg, IMG_0001.png" "$w/ext/err"'
assert "jpeg + png: nothing written"           '[[ ! -e "$w/ext/out" ]]'
assert "jpeg + png: summary on stderr"         'grep -q "^mediamill: 1 output name(s) claimed by more than one source" "$w/ext/err"'
assert "jpeg + png: stdout empty"              '[[ ! -s "$w/ext/log" ]]'

mk three a/x.heic a/x.webp a/x.jpg
run three
assert "three sources: one group of three"    'grep -qxF "CLASH a/x.jpg <- a/x.heic, a/x.jpg, a/x.webp" "$w/three/err"'

mk gif clip.gif clip.mp4
run gif
assert "gif + mp4 copy: clash"                 '[[ $rc -eq 3 ]] && grep -q "^CLASH clip.mp4 <- " "$w/gif/err"'

mk dir foo.jpg/inner.txt foo.png
run dir
assert "target is a directory: clash"          '[[ $rc -eq 3 ]] && grep -qxF "CLASH foo.jpg <- foo.jpg/, foo.png" "$w/dir/err"'

# Targets that differ only in case clash: on case-insensitive filesystems they are one file.
mk case Pic.png pic.webp
run case
assert "case-only target difference: clash"   '[[ $rc -eq 3 ]] && grep -qxF "CLASH Pic.jpg <- Pic.png, pic.webp" "$w/case/err"'

mk many b.png b.webp c.gif c.mp4
run many
assert "two groups: two CLASH lines, sorted"   '[[ "$(grep "^CLASH" "$w/many/err" | cut -d" " -f2 | tr "\n" " ")" == "b.jpg c.mp4 " ]]'
assert "two groups: count in summary"          'grep -q "^mediamill: 2 output name(s)" "$w/many/err"'

mk odd "we]i'rd *.png" "we]i'rd *.jpg"
run odd
assert "odd characters in names: clash"        '[[ $rc -eq 3 ]] && grep -qxF "CLASH we]i'"'"'rd *.jpg <- we]i'"'"'rd *.jpg, we]i'"'"'rd *.png" "$w/odd/err"'

# No clash: same stem in different dirs, a non-media file sharing the stem, a lone .jpg
mk ok p/IMG.png q/IMG.png IMG.jpg IMG.txt anim.gif
run ok
assert "clean tree: exit 0"                    '[[ $rc -eq 0 ]]'
assert "clean tree: every target written"      '[[ -s "$w/ok/out/p/IMG.jpg" && -s "$w/ok/out/q/IMG.jpg" && -s "$w/ok/out/IMG.jpg" && -s "$w/ok/out/IMG.txt" && -s "$w/ok/out/anim.mp4" ]]'
assert "clean tree: no _2 names"               '[[ -z "$(find "$w/ok/out" -name "*_2*")" ]]'
assert "clean tree: nothing on stderr"         '[[ ! -s "$w/ok/err" ]]'

print "failures: $fails"; exit $(( fails > 0 ))
