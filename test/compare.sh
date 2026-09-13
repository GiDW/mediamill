#!/usr/bin/env zsh
# Golden test: legacy script (native) vs candidate (native tool or container image).
# Usage: test/compare.sh native | container [image]      (default image localhost/mediamill:dev)
set -u
mode="${1:?native|container}"; image="${2:-localhost/mediamill:dev}"
here="${0:A:h}"; root="${here:h}"
work="/private/tmp/mm-compare"; rm -rf -- "$work"; mkdir -p "$work"
"$here/make-corpus.sh" "$work/corpus" 4 >/dev/null

print "== legacy (native)"; zsh "$here/legacy/converttojpg.sh" "$work/corpus" "$work/golden" >"$work/legacy.log" 2>&1 || { print -u2 "legacy failed"; exit 1 }

print "== candidate ($mode)"
case "$mode" in
  native)    time "$root/bin/mediamill" "$work/corpus" "$work/cand" >"$work/cand.log" 2>&1 ;;
  container) mkdir -p "$work/cand"
             time podman run --rm --init --userns=keep-id:uid=65532,gid=65532 \
               -v "$work/corpus:/in:ro" -v "$work/cand:/out" "$image" /in /out >"$work/cand.log" 2>&1 ;;
  *) print -u2 "unknown mode"; exit 1 ;;
esac
rc=$?; (( rc == 0 )) || { print -u2 "candidate exited $rc"; tail -20 "$work/cand.log"; exit 1 }

if command -v md5 >/dev/null; then hasher=(md5 -r); else hasher=(md5sum); fi   # macOS vs Linux; each platform compares with itself
sums() { (cd "$1" && find . -type f ! -name '*.mp4' -exec "${hasher[@]}" {} \;) | sort -k2 }
if diff <(sums "$work/golden") <(sums "$work/cand") >"$work/diff.txt"; then
  print "identical: $(sums "$work/golden" | wc -l | tr -d ' ') files"
else
  print -u2 "DIFFERENCES:"; cat "$work/diff.txt"; exit 1
fi
for f in $(cd "$work/golden" && find . -name '*.mp4'); do
  [[ -s "$work/cand/$f" ]] || { print -u2 "missing mp4 $f"; exit 1 }
  ffprobe -v error "$work/cand/$f" || { print -u2 "unplayable mp4 $f"; exit 1 }
done
print "PASS"
