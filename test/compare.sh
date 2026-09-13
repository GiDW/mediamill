#!/usr/bin/env zsh
# Golden test: legacy script (native) vs candidate (native tool or container image).
# Usage: test/compare.sh native | container [image]      (default image localhost/mediamill:dev)
set -u
mode="${1:?native|container}"; image="${2:-localhost/mediamill:dev}"
here="${0:A:h}"; root="${here:h}"
work="/private/tmp/mm-compare"; rm -rf -- "$work"; mkdir -p "$work"
"$here/make-corpus.sh" "$work/corpus" 4 >/dev/null || { print -u2 "make-corpus failed"; exit 1 }

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
golden_sums="$(sums "$work/golden")"
if diff <(print -r -- "$golden_sums") <(sums "$work/cand") >"$work/diff.txt"; then
  n="$(print -r -- "$golden_sums" | wc -l | tr -d ' ')"
  (( n > 0 )) || { print -u2 "no files compared (empty golden output?)"; exit 1 }
  print "identical: $n files"
else
  print -u2 "DIFFERENCES:"; cat "$work/diff.txt"; exit 1
fi
# zsh glob, not word-split find output: an mp4 under "sub one/" keeps its path intact.
for f in "$work"/golden/**/*.mp4(.N); do
  f="${f#$work/golden/}"
  [[ -s "$work/cand/$f" ]] || { print -u2 "missing mp4 $f"; exit 1 }
  ffprobe -v error "$work/cand/$f" || { print -u2 "unplayable mp4 $f"; exit 1 }
done
# --quiet must produce no stdout at all (stderr and exit code unchanged); only meaningful natively.
if [[ "$mode" == native ]]; then
  q="$("$root/bin/mediamill" --quiet --force "$work/corpus" "$work/cand" 2>"$work/quiet.err")"; rc=$?
  [[ $rc -eq 0 && -z "$q" ]] || { print -u2 "quiet mode: rc=$rc stdout=[$q]"; cat "$work/quiet.err" >&2; exit 1 }
  [[ ! -s "$work/quiet.err" ]] || { print -u2 "quiet mode wrote to stderr on success:"; cat "$work/quiet.err" >&2; exit 1 }
fi
# PDF flow: native reference from the fixture; container mode must match it byte for byte.
pdf="$here/fixtures/tiny.pdf"
"$root/bin/mediamill" --quiet "$pdf" "$work/pdf-native" || { print -u2 "pdf native failed"; exit 1 }
[[ -s "$work/pdf-native/0000.jpg" && -s "$work/pdf-native/0001.jpg" ]] || { print -u2 "pdf native: expected 0000.jpg 0001.jpg"; ls "$work/pdf-native" >&2; exit 1 }
if [[ "$mode" == container ]]; then
  mkdir -p "$work/pdf-cand"
  podman run --rm --init --userns=keep-id:uid=65532,gid=65532 -v "$pdf:/in/tiny.pdf:ro" -v "$work/pdf-cand:/out" "$image" --quiet /in/tiny.pdf /out \
    || { print -u2 "pdf container failed"; exit 1 }
  diff <(sums "$work/pdf-native") <(sums "$work/pdf-cand") || { print -u2 "pdf: container output differs from native"; exit 1 }
  print "pdf: identical"
fi
print "PASS"
