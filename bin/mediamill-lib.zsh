# Sourced by bin/mediamill and bin/mediamill-worker: the single definition of what a file
# becomes. The wrapper's clash preflight and the worker must agree on every target name.
# Both functions set REPLY instead of printing, so the preflight can call them per file
# without forking a subshell.

# REPLY = image | video | other, for a lowercase extension $1.
mm_kind() {
  case "$1" in
    jpg|jpeg|jp2|jfif|pjpeg|pjp|png|webp|heic) REPLY=image ;;
    gif) REPLY=video ;;
    *) REPLY=other ;;
  esac
}

# REPLY = output path for input path $1 (relative or absolute; only the extension changes).
mm_target() {
  mm_kind "${${1:e}:l}"
  case "$REPLY" in
    image) REPLY="${1:r}.${MM_PIC_EXT:-jpg}" ;;
    video) REPLY="${1:r}.${MM_VID_EXT:-mp4}" ;;
    *) REPLY="$1" ;;
  esac
}
