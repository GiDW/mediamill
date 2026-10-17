#!/usr/bin/env zsh
# Argument and environment validation of libexec/mediamill. Needs no media tools: vips/ffmpeg
# are replaced by `true` and the input is empty, so a valid run ends at "nothing to do".
set -u
here="${0:A:h}"; mm="$here/../libexec/mediamill"
w="$(mktemp -d)"; trap 'rm -rf -- "$w"' EXIT
fails=0
assert() { if eval "$2"; then print "ok   $1"; else print "FAIL $1"; fails=$((fails+1)); fi }
export MM_VIPS=true MM_FFMPEG=true
mkdir -p "$w/in"

# run [env assignments...] -- [args...]: rc in $rc, stderr in $w/err
run() { local -a envs; while [[ "$1" != -- ]]; do envs+=("$1"); shift; done; shift
        env "${envs[@]}" "$mm" "$@" "$w/in" "$w/out" >/dev/null 2>"$w/err"; rc=$? }

for bad in 0 abc -1 2x; do
  run MM_JOBS="$bad" --
  assert "MM_JOBS='$bad': usage error (exit 1)"  '[[ $rc -eq 1 ]] && grep -q "^MM_JOBS must be a positive integer" "$w/err"'
done
run MM_JOBS=abc -- --jobs 2
assert "valid --jobs overrides bad MM_JOBS"     '[[ $rc -eq 0 ]]'
run MM_JOBS=3 --
assert "MM_JOBS=3 accepted"                     '[[ $rc -eq 0 ]]'
for bad in 0 abc; do
  run -- --jobs "$bad"
  assert "--jobs $bad: usage error (exit 1)"    '[[ $rc -eq 1 ]] && grep -q "^usage:" "$w/err"'
done
# --format: lowercase jpg|jxl|avif only; with no value it swallows the input and still fails
for bad in bmp JPG ""; do
  run -- --format "$bad"
  assert "--format '$bad': usage error (exit 1)" '[[ $rc -eq 1 ]] && grep -q "^usage:" "$w/err"'
done
run -- --format
assert "--format without a value: usage error" '[[ $rc -eq 1 ]] && grep -q "^usage:" "$w/err"'
"$mm" --format >/dev/null 2>"$w/err"; rc=$?
assert "--format as the last argument: usage error" '[[ $rc -eq 1 ]] && grep -q "^usage:" "$w/err"'
run -- --format=jxl
assert "--format=jxl accepted"                  '[[ $rc -eq 0 ]]'
run -- --format avif
assert "--format avif accepted"                 '[[ $rc -eq 0 ]]'
run MM_FORMAT=webp --
assert "MM_FORMAT=webp: usage error (exit 1)"   '[[ $rc -eq 1 ]] && grep -q "^MM_FORMAT must be one of jpg, jxl, avif, got: webp" "$w/err"'
run MM_FORMAT=webp -- --format avif
assert "valid --format overrides bad MM_FORMAT" '[[ $rc -eq 0 ]]'
run MM_FORMAT=jxl --
assert "MM_FORMAT=jxl accepted"                 '[[ $rc -eq 0 ]]'
# --encoder-opts: syntax is checked up front (the stubbed vips accepts any name, see single.test.sh)
for bad in "Q=[5]" "Q=65,," "=5"; do
  run -- --encoder-opts "$bad"
  assert "--encoder-opts '$bad': usage error"  '[[ $rc -eq 1 ]] && grep -q "^usage:" "$w/err"'
done
"$mm" --encoder-opts >/dev/null 2>"$w/err"; rc=$?
assert "--encoder-opts without a value: usage error" '[[ $rc -eq 1 ]] && grep -q "^usage:" "$w/err"'
run -- --encoder-opts 'Q=65,effort=6'
assert "--encoder-opts Q=65,effort=6 accepted" '[[ $rc -eq 0 ]]'
run -- --encoder-opts=Q=65
assert "--encoder-opts=Q=65 accepted"           '[[ $rc -eq 0 ]]'
run MM_ENCODER_OPTS='Q=]' --
assert "bad MM_ENCODER_OPTS: usage error"       '[[ $rc -eq 1 ]] && grep -q "^MM_ENCODER_OPTS must be a comma-separated list of name or name=value, got: Q=]" "$w/err"'
run MM_ENCODER_OPTS='Q=]' -- --encoder-opts Q=60
assert "valid --encoder-opts overrides bad MM_ENCODER_OPTS" '[[ $rc -eq 0 ]]'

print "failures: $fails"; exit $(( fails > 0 ))
