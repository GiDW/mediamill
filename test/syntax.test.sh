#!/usr/bin/env zsh
# zsh -n (parse only, nothing runs) on every zsh script in the repository. Needs only zsh.
set -u
here="${0:A:h}"; root="${here:h}"
fails=0 n=0
for f in "$root"/bin/*(.N) "$root"/libexec/*(.N) "$root"/test/*.sh(.N); do
  n=$((n+1))
  if err="$(zsh -n -- "$f" 2>&1)"; then print -r -- "ok   ${f#$root/}"
  else print -r -- "FAIL ${f#$root/}: $err"; fails=$((fails+1)); fi
done
(( n > 0 )) || { print "FAIL no scripts found"; fails=1 }
print "failures: $fails"; exit $(( fails > 0 ))
