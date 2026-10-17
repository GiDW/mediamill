#!/usr/bin/env zsh
# Single-file mode of libexec/mediamill with --format, and the --encoder-opts preflight. Requires vips + vipsheader (the image has them).
set -u
here="${0:A:h}"; mm="$here/../libexec/mediamill"
w="$(mktemp -d)"; trap 'rm -rf -- "$w"' EXIT
fails=0
assert() { if eval "$2"; then print "ok   $1"; else print "FAIL $1"; fails=$((fails+1)); fi }
vips black "$w/a.png" 32 32
mkdir -p "$w/cwd"; cd "$w/cwd"

"$mm" --format avif "$w/a.png" >/dev/null 2>&1; rc=$?
assert "default name follows the format (a.avif)" '[[ $rc -eq 0 && -s a.avif && "$(vipsheader -f vips-loader a.avif)" == heifload ]]'
"$mm" --format avif "$w/a.png" >/dev/null 2>&1
assert "second run without output gets a_2.avif"  '[[ -s a_2.avif ]]'
"$mm" "$w/a.png" >/dev/null 2>&1
assert "no --format: a.jpg"                       '[[ -s a.jpg && "$(vipsheader -f vips-loader a.jpg)" == jpegload ]]'
"$mm" --format jxl "$w/a.png" "$w/o/OUT.JXL" >/dev/null 2>&1; rc=$?
assert "uppercase explicit extension accepted"     '[[ $rc -eq 0 && "$(vipsheader -f vips-loader "$w/o/OUT.JXL")" == jxlload ]]'
"$mm" --format jpg "$w/a.png" "$w/o/x.JPEG" >/dev/null 2>&1; rc=$?
assert "jpg accepts .JPEG"                          '[[ $rc -eq 0 && -s "$w/o/x.JPEG" ]]'
"$mm" --format avif "$w/a.png" "$w/o/wrong.jpg" >/dev/null 2>"$w/err"; rc=$?
assert "mismatched extension: exit 1, nothing written" '[[ $rc -eq 1 && ! -e "$w/o/wrong.jpg" ]] && grep -q "^output must end in .avif for --format avif" "$w/err"'
"$mm" "$w/a.png" "$w/o/wrong.webp" >/dev/null 2>"$w/err"; rc=$?
assert "jpg into .webp rejected too"               '[[ $rc -eq 1 && ! -e "$w/o/wrong.webp" ]]'

# An option vips does not know fails once, up front, with nothing written (any mode)
"$mm" --format avif --encoder-opts 'Q=60,bogus=1' "$w/a.png" "$w/o/b.avif" >/dev/null 2>"$w/err"; rc=$?
assert "unknown encoder option: exit 1, nothing written" '[[ $rc -eq 1 && ! -e "$w/o/b.avif" ]] && grep -q "^mediamill: invalid --encoder-opts for avif" "$w/err"'
mkdir -p "$w/tree"; cp "$w/a.png" "$w/tree/"
"$mm" --encoder-opts 'bogus=1' "$w/tree" "$w/tout" >/dev/null 2>"$w/err"; rc=$?
assert "directory mode: same preflight, nothing written" '[[ $rc -eq 1 && ! -e "$w/tout" ]] && ! grep -q "^FAIL" "$w/err"'
"$mm" --format jxl --encoder-opts 'Q=40' "$w/a.png" "$w/o/c.jxl" >/dev/null 2>&1; rc=$?
assert "valid encoder option converts"           '[[ $rc -eq 0 && "$(vipsheader -f vips-loader "$w/o/c.jxl")" == jxlload ]]'

print "failures: $fails"; exit $(( fails > 0 ))
