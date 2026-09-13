#!/usr/bin/env zsh
# PDF input flow of bin/mediamill. Requires vips, ffmpeg, pdfimages, vipsheader on PATH.
set -u
zmodload zsh/stat; mtime() { zstat +mtime -- "$1" }
here="${0:A:h}"; mm="$here/../bin/mediamill"; pdf="$here/fixtures/tiny.pdf"
w="$(mktemp -d)"; trap 'rm -rf -- "$w"' EXIT
fails=0
assert() { if eval "$2"; then print "ok   $1"; else print "FAIL $1"; fails=$((fails+1)); fi }

# default output folder ./<stem>/ in cwd
cd "$w"
"$mm" "$pdf" >"$w/out1.txt" 2>"$w/err1.txt"; rc=$?
assert "pdf → ./tiny/ exit 0"                 '[[ $rc -eq 0 && -d tiny ]]'
assert "two sequence-named jpgs"              '[[ -s tiny/0000.jpg && -s tiny/0001.jpg && "$(ls tiny | wc -l | tr -d " ")" == 2 ]]'
assert "outputs are jpeg"                     '[[ "$(vipsheader -f vips-loader tiny/0000.jpg)" == jpegload && "$(vipsheader -f vips-loader tiny/0001.jpg)" == jpegload ]]'
assert "status lines JPG 0000.png / 0001.jpg" 'grep -q "^JPG 0000.png$" out1.txt && grep -q "^JPG 0001.jpg$" out1.txt'
assert "PDF summary line"                     'grep -q "^PDF tiny.pdf: 2 images$" out1.txt'
assert "nothing on stderr"                    '[[ ! -s err1.txt ]]'

# re-run is incremental (targets newer than the pdf → SKIP), --force redoes
m1="$(mtime tiny/0000.jpg)"; sleep 1
"$mm" "$pdf" >"$w/out2.txt" 2>&1
assert "re-run skips both"                    '[[ "$(grep -c "^SKIP" out2.txt)" == 2 && "$(mtime tiny/0000.jpg)" == "$m1" ]]'
"$mm" --force "$pdf" >"$w/out3.txt" 2>&1
assert "--force reconverts"                   '[[ "$(grep -c "^JPG" out3.txt)" == 2 && "$(mtime tiny/0000.jpg)" != "$m1" ]]'

# a newer pdf (re-saved) is reconverted without --force
cp -- "$pdf" newer.pdf; sleep 1; touch newer.pdf
"$mm" newer.pdf >/dev/null 2>&1; sleep 1; touch newer.pdf
"$mm" newer.pdf >"$w/out4.txt" 2>&1
assert "newer pdf → reconvert"                '[[ "$(grep -c "^JPG" out4.txt)" == 2 ]]'

# explicit output folder, created, nested
"$mm" "$pdf" "$w/deep/er/target" >/dev/null 2>&1; rc=$?
assert "explicit out-dir created"             '[[ $rc -eq 0 && -s "$w/deep/er/target/0001.jpg" ]]'

# --extract-only keeps native formats and lowercases extensions
"$mm" --extract-only "$pdf" "$w/raw" >"$w/out5.txt" 2>&1; rc=$?
assert "extract-only: png + jpg kept"         '[[ $rc -eq 0 && -s "$w/raw/0000.png" && -s "$w/raw/0001.jpg" && ! -e "$w/raw/0000.jpg" ]]'
assert "extract-only: status lines"           'grep -q "^RAW 0000.png$" out5.txt && grep -q "^PDF tiny.pdf: 2 images$" out5.txt'
"$mm" --extract-only "$pdf" "$w/raw" >/dev/null 2>&1; rc=$?
assert "extract-only re-run overwrites, exit 0" '[[ $rc -eq 0 && -s "$w/raw/0000.png" ]]'

# --quiet: nothing on stdout
q="$("$mm" --quiet --force "$pdf" "$w/quiet" 2>&1)"; rc=$?
assert "--quiet silent, exit 0"               '[[ $rc -eq 0 && -z "$q" ]]'

# errors
"$mm" --extract-only tiny/0000.jpg >/dev/null 2>"$w/err6.txt"; rc=$?
assert "--extract-only with non-pdf → usage"  '[[ $rc -eq 1 ]] && grep -q "extract-only" err6.txt'
printf 'not a pdf' > broken.pdf
"$mm" broken.pdf >/dev/null 2>"$w/err7.txt"; rc=$?
assert "broken pdf → FAIL, exit 2"            '[[ $rc -eq 2 ]] && grep -q "^FAIL broken.pdf" err7.txt'
assert "broken pdf leaves no folder content"  '[[ -z "$(ls broken 2>/dev/null)" ]]'
"$mm" "$pdf" newer.pdf >/dev/null 2>"$w/err8.txt"; rc=$?
assert "out-dir is a file → error 1"          '[[ $rc -eq 1 ]] && grep -q "expected a directory" err8.txt'

# directory mode is unchanged: a pdf inside a tree is copied, not extracted
mkdir -p tree/in && cp -- "$pdf" tree/in/doc.pdf
"$mm" tree/in tree/out >"$w/out9.txt" 2>&1
assert "dir mode copies pdf unchanged"        'grep -q "^CP doc.pdf$" out9.txt && cmp -s "$pdf" tree/out/doc.pdf && [[ ! -d tree/out/doc ]]'

print "failures: $fails"; exit $(( fails > 0 ))
