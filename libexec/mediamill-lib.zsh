# Sourced by libexec/mediamill and libexec/mediamill-worker: the single definition of what a file
# becomes. The wrapper's clash preflight and the worker must agree on every target name.
# All functions set REPLY instead of printing, so the preflight can call them per file
# without forking a subshell.

# Image output formats; the name is also the output extension. MM_FORMAT selects one (default jpg).
typeset -ga mm_formats=(jpg jxl avif)

# REPLY = default vips save options for format $1. jpg is the historic mozjpeg encode (sRGB, no
# metadata); jxl/avif keep the ICC profile, so wide-gamut sources stay wide gamut.
mm_vips_opts() {
  case "$1" in
    jpg)  REPLY='[Q=75,keep=none,trellis-quant,interlace,optimize-coding,optimize-scans,quant-table=3,subsample_mode=on]' ;;
    jxl)  REPLY='[Q=75,keep=icc]' ;;
    avif) REPLY='[Q=50,keep=icc,bitdepth=8,subsample_mode=off,effort=6,encoder=aom]' ;;
  esac
}

# REPLY = the stdout status tag for format $1 (JPG, JXL, AVIF).
mm_format_tag() { REPLY="${(U)1}" }

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
    image) REPLY="${1:r}.${MM_FORMAT:-jpg}" ;;
    video) REPLY="${1:r}.${MM_VID_EXT:-mp4}" ;;
    *) REPLY="$1" ;;
  esac
}
