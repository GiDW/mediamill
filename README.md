# mediamill

Recursively converts an image tree to optimised JPEG (libvips + mozjpeg) and GIFs to MP4 (ffmpeg), copying everything else.
Runs as a container so macOS and Linux produce identical bytes.

    mediamill [--jobs N] [--force] <input-dir> <output-dir>
    mediamill <image>              # -> <stem>.jpg in the current dir
    mediamill <image> <out.jpg>

Re-runs are incremental: a target that exists and is newer than its source is skipped; `--force` redoes everything.
Outputs whose source was removed are never deleted.

Image: `ghcr.io/gidw/mediamill`. Host wrapper: `host/mediamill.zsh` (source it from `~/.zshrc`).
Tests: `test/compare.sh native` (needs Homebrew vips with mozjpeg) and `test/compare.sh container`.

License: MIT (see `LICENSE`) for the code in this repo. The published image also bundles third-party software under its own licences: libvips (LGPL-2.1-or-later), mozjpeg (BSD-style), and a static ffmpeg build that includes libx264 (GPL).
