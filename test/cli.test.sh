#!/usr/bin/env zsh
# Argument and environment validation of bin/mediamill. Needs no media tools: vips/ffmpeg
# are replaced by `true` and the input is empty, so a valid run ends at "nothing to do".
set -u
here="${0:A:h}"; mm="$here/../bin/mediamill"
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

print "failures: $fails"; exit $(( fails > 0 ))
