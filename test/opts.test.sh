#!/usr/bin/env zsh
# Encoder option merging and validation in libexec/mediamill-lib.zsh. Needs only zsh.
set -u
here="${0:A:h}"
source "$here/../libexec/mediamill-lib.zsh" || exit 1
fails=0
assert() { if eval "$2"; then print "ok   $1"; else print "FAIL $1"; fails=$((fails+1)); fi }
merged() { mm_vips_opts "$1"; mm_merge_opts "$REPLY" "$2"; print -r -- "$REPLY" }

assert "no user options: defaults unchanged" \
  '[[ "$(merged avif "")" == "[Q=55,keep=icc,bitdepth=8,subsample_mode=off,effort=4,encoder=aom]" ]]'
assert "user value replaces the default in place" \
  '[[ "$(merged avif "Q=65,effort=6")" == "[Q=65,keep=icc,bitdepth=8,subsample_mode=off,effort=6,encoder=aom]" ]]'
assert "new setting appended at the end" \
  '[[ "$(merged jxl "effort=9")" == "[Q=80,keep=icc,effort=9]" ]]'
assert "bare switch replaced by name=value" \
  '[[ "$(merged jpg "interlace=false")" == "[Q=75,keep=none,trellis-quant,interlace=false,optimize-coding,optimize-scans,quant-table=3,subsample_mode=on]" ]]'
assert "_ and - name the same setting" \
  '[[ "$(merged jpg "subsample-mode=off,quant_table=2")" == "[Q=75,keep=none,trellis-quant,interlace,optimize-coding,optimize-scans,quant_table=2,subsample-mode=off]" ]]'
assert "repeated user setting: last one wins, once" \
  '[[ "$(merged jxl "Q=60,Q=70")" == "[Q=70,keep=icc]" ]]'
assert "keep=all is honoured" \
  '[[ "$(merged jpg "keep=all")" == "[Q=75,keep=all,trellis-quant,interlace,optimize-coding,optimize-scans,quant-table=3,subsample_mode=on]" ]]'

for good in "Q=65" "trellis-quant" "keep=all,Q=1" "subsample_mode=off" "profile=/x y/p.icc"; do
  assert "valid: '$good'"   'mm_valid_opts "$good"'
done
for bad in "" "," "Q=65," "Q=65,,effort=1" "=5" "Q=" "[Q=5]" "Q=5]" "Q=[5" "9Q=5" "Q=5=6"; do
  assert "invalid: '$bad'"  '! mm_valid_opts "$bad"'
done

print "failures: $fails"; exit $(( fails > 0 ))
