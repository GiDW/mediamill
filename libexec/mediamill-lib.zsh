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
    jxl)  REPLY='[Q=80,keep=icc]' ;;
    avif) REPLY='[Q=55,keep=icc,bitdepth=8,subsample_mode=off,effort=4,encoder=aom]' ;;
  esac
}

# Succeeds if $1 is a non-empty comma-separated list of name or name=value, the syntax of a vips
# option string. Brackets, an empty item or an empty value cannot be passed through to vips.
mm_valid_opts() {
  setopt localoptions extendedglob
  local tok
  [[ -n "$1" ]] || return 1
  for tok in "${(@s:,:)1}"; do
    [[ "$tok" == [A-Za-z][A-Za-z0-9_-]#(|=[^][=]##) ]] || return 1
  done
}

# REPLY = the defaults $1 ("[a,b=1,...]") with each setting of $2 ("b=2,c") replacing the one of
# the same name in place, or appended when new. A bare switch (interlace) is replaced by
# interlace=false the same way. Names compare with _ and - as equal, as vips treats them.
mm_merge_opts() {
  local tok key
  local -a order out
  local -A val
  for tok in ${(s:,:)${${1#\[}%\]}} ${(s:,:)2}; do
    key="${${tok%%=*}//_/-}"
    (( ${+val[$key]} )) || order+=("$key")
    val[$key]="$tok"
  done
  for key in $order; do out+=("${val[$key]}"); done
  REPLY="[${(j:,:)out}]"
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
