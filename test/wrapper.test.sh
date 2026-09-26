#!/usr/bin/env zsh
# Host wrapper bin/mediamill: the podman command it assembles. podman is replaced by a stub on
# PATH that records its arguments, so this needs neither podman nor the image.
set -u
here="${0:A:h}"; wrapper="$here/../bin/mediamill"
w="$(mktemp -d)"; trap 'rm -rf -- "$w"' EXIT
w="${w:A}"   # the wrapper resolves paths (macOS: /var -> /private/var); expectations must match
fails=0
assert() { if eval "$2"; then print "ok   $1"; else print "FAIL $1"; fails=$((fails+1)); fi }
mkdir -p "$w/stub" "$w/in/sub" "$w/cwd"; touch "$w/in/a b.png"
print -r -- '#!/bin/sh
: > "$STUB_ARGS"; for a in "$@"; do printf "%s\n" "$a" >> "$STUB_ARGS"; done; exit "${STUB_RC:-0}"' > "$w/stub/podman"
chmod +x "$w/stub/podman"
export PATH="$w/stub:$PATH" STUB_ARGS="$w/args"
unset MEDIAMILL_IMAGE MM_JOBS

# run [args...]: from $w/cwd, stdin not a terminal (so no -it); rc in $rc, podman argv in $got
run() { rm -f -- "$w/args"; (cd "$w/cwd" && "$wrapper" "$@" </dev/null >/dev/null 2>"$w/err"); rc=$?
        got="$(cat "$w/args" 2>/dev/null)" }
base=(run --rm --init --userns=keep-id:uid=65532,gid=65532 -w /out)
[[ "$OSTYPE" == linux* ]] && base+=(--group-add keep-groups)
img=ghcr.io/gidw/mediamill:latest
want() { print -rl -- "${base[@]}" "$@" }

run "$w/in" "$w/out"
assert "directory: ro input, output mounted, /in /out" '[[ $rc -eq 0 && "$got" == "$(want -v "$w/in:/in:ro" -v "$w/out:/out" $img /in /out)" ]]'
assert "directory: output created on the host" '[[ -d "$w/out" ]]'
run --jobs 3 --force "$w/in" "$w/out"
assert "options passed through after the image" '[[ "$got" == "$(want -v "$w/in:/in:ro" -v "$w/out:/out" $img --jobs 3 --force /in /out)" ]]'
run "$w/in/a b.png"
assert "file, no output: parent ro, cwd as /out"  '[[ $rc -eq 0 && "$got" == "$(want -v "$w/in:/in:ro" -v "$w/cwd:/out" $img "/in/a b.png")" ]]'
run --quiet "$w/in/a b.png" "$w/o/deep/x.jpg"
assert "file with output: its parent as /out"     '[[ "$got" == "$(want -v "$w/in:/in:ro" -v "$w/o/deep:/out" $img --quiet "/in/a b.png" /out/x.jpg)" ]]'
assert "file with output: parent created"         '[[ -d "$w/o/deep" ]]'
(cd "$w/cwd" && ln -s ../in rel) && run rel/"a b.png" x.jpg
assert "relative paths resolved (through a symlink)" '[[ "$got" == "$(want -v "$w/in:/in:ro" -v "$w/cwd:/out" $img "/in/a b.png" /out/x.jpg)" ]]'
MM_JOBS=2 run "$w/in" "$w/out"
assert "MM_JOBS forwarded"                        '[[ "$got" == "$(want -e MM_JOBS -v "$w/in:/in:ro" -v "$w/out:/out" $img /in /out)" ]]'
MEDIAMILL_IMAGE=localhost/mediamill:dev run "$w/in" "$w/out"
assert "MEDIAMILL_IMAGE honoured"                 '[[ "$got" == *$'"'"'\nlocalhost/mediamill:dev\n'"'"'* ]]'
run --help
assert "--help runs the image's help"             '[[ $rc -eq 0 && "$got" == "$(print -l run --rm $img --help)" ]]'
STUB_RC=2 run "$w/in" "$w/out"
assert "podman exit code passed through"          '[[ $rc -eq 2 ]]'
ln -s "$wrapper" "$w/stub/mediamill"
(cd "$w/cwd" && mediamill "$w/in" "$w/out2" </dev/null >/dev/null 2>&1); rc=$?
assert "runs from PATH through a symlink"         '[[ $rc -eq 0 && -d "$w/out2" ]]'

# usage and input errors: exit 1, podman never called
for c in "" "$w/in" "$w/missing $w/out" "$w/in $w/in/sub" "$w/in $w/in" "a b c"; do
  run ${=c}
  assert "error '${c//$w/…}': exit 1, no podman" '[[ $rc -eq 1 && ! -e "$w/args" && -s "$w/err" ]]'
done

print "failures: $fails"; exit $(( fails > 0 ))
