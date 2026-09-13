# Source from ~/.zshrc. Runs ghcr.io/gidw/mediamill via podman with the right mounts.
# Usage identical to the tool: mediamill [--jobs N] [--force] <input> [output]
# macOS: paths must live under /Users, /private or /var/folders (podman machine shares only those).
mediamill() {
  local image="${MEDIAMILL_IMAGE:-ghcr.io/gidw/mediamill:latest}"
  local -a opts mounts run
  while (( $# )) && [[ "$1" == --* ]]; do
    opts+=("$1"); [[ "$1" == --jobs && $# -ge 2 ]] && { opts+=("$2"); shift }; shift
  done
  (( ${opts[(I)--help]} )) && { podman run --rm "$image" --help; return $? }
  (( $# >= 1 && $# <= 2 )) || { print -u2 "usage: mediamill [--jobs N] [--force] <input> [output]"; return 1 }
  local input="$1" output="${2:-}" ctr_in ctr_out
  [[ -e "$input" ]] || { print -u2 "mediamill: no such input: $input"; return 1 }
  local in_abs="${input:A}"
  if [[ -d "$in_abs" ]]; then
    [[ -n "$output" ]] || { print -u2 "mediamill: output directory required"; return 1 }
    local out_abs="${output:A}"
    [[ "$out_abs" == "$in_abs" || "$out_abs" == "$in_abs"/* ]] && { print -u2 "mediamill: output must not be the input or inside it"; return 1 }
    mkdir -p -- "$output" || return 1
    mounts=(-v "${in_abs}:/in:ro" -v "${out_abs}:/out"); ctr_in=/in; ctr_out=/out
  else
    mounts=(-v "${in_abs:h}:/in:ro"); ctr_in="/in/${in_abs:t}"
    if [[ -n "$output" ]]; then
      mkdir -p -- "${output:A:h}" || return 1
      mounts+=(-v "${output:A:h}:/out"); ctr_out="/out/${output:t}"
    else
      mounts+=(-v "${PWD:A}:/out"); ctr_out=""
    fi
  fi
  run=(podman run --rm --init --userns=keep-id:uid=65532,gid=65532 -w /out)
  [[ "$OSTYPE" == linux* ]] && run+=(--group-add keep-groups)
  [[ -t 0 && -t 1 ]] && run+=(-it)
  [[ -n "${MM_JOBS:-}" ]] && run+=(-e MM_JOBS)
  "${run[@]}" "${mounts[@]}" "$image" "${opts[@]}" "$ctr_in" ${ctr_out:+"$ctr_out"}
}
