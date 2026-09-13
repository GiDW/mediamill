# mediamill

Recursively converts a tree of images to optimised JPEG (libvips with mozjpeg) and animated GIFs to MP4 (ffmpeg), copying every other file unchanged. Directory structure is mirrored, files are processed in parallel, and re-runs only touch what changed.

It runs as a container, so a Mac and a Linux server produce byte-identical output from one image: `ghcr.io/gidw/mediamill` (linux/amd64 and linux/arm64).

## What happens to each file

| Input extension (any case) | Result |
|---|---|
| `jpg` `jpeg` `jp2` `jfif` `pjpeg` `pjp` `png` `webp` `heic` | `<name>.jpg`, encoded with `Q=75, strip, trellis-quant, interlace, optimize-coding, optimize-scans, quant-table=3, subsample_mode=on` |
| `gif` | `<name>.mp4`, `libx264 -crf 24 -preset slow`, `yuv420p`, even dimensions, `faststart` |
| anything else | copied as is |

If a source `photo.png` sits next to a different file `photo.jpg`, the converted PNG becomes `photo_2.jpg` so the two do not overwrite each other. On case-insensitive filesystems `PHOTO.JPG` and `photo.jpg` are recognised as the same file.

## Requirements

- Podman with a working rootless setup. On macOS that means a running `podman machine`; on Linux, rootless podman with `crun` (the default on Arch and Fedora).
- zsh on the host for the wrapper function. Nothing else: vips and ffmpeg live inside the image.

## Install

Copy or source the wrapper from your shell startup file:

```sh
git clone https://github.com/GiDW/mediamill [CHOSEN_MEDIAMILL_PATH]
echo 'source [CHOSEN_MEDIAMILL_PATH]/host/mediamill.zsh' >> ~/.zshrc
exec zsh
```

The first run pulls the image (about 90 MB compressed). Update later with `podman pull ghcr.io/gidw/mediamill:latest`.

## Usage

```
mediamill [--jobs N] [--force] <input-dir> <output-dir>
mediamill [--force] <image|gif> [<output-file>]
mediamill --help
```

Convert a whole tree. The output directory is created if needed and must not be the input or inside it:

```sh
mediamill ~/Pictures/2026-trip ~/Pictures/2026-trip-web
```

Convert a single file into the current directory (`IMG_0042.jpg`; a second run without `--force` skips it, a name clash gets `_2`, `_3`, …):

```sh
cd ~/Desktop
mediamill ~/Pictures/IMG_0042.heic
```

Convert a single file to an explicit path (parent directories are created):

```sh
mediamill ~/Downloads/funny.gif ~/Videos/clips/funny.mp4
```

Limit parallelism, for example on a shared machine:

```sh
mediamill --jobs 2 ~/Pictures/raw ~/Pictures/out
```

### Re-runs

A target that already exists and is newer than its source is skipped, so interrupting a run and starting it again continues where it stopped, and adding new files to the input converts only those. `--force` rewrites everything. Outputs whose source was removed are never deleted.

Files are written to a temporary name and renamed when complete, so a killed run leaves no half-written output. Ctrl-C stops all workers.

### Options and environment

| Option / variable | Meaning | Default |
|---|---|---|
| `--jobs N` | files converted in parallel | number of CPUs visible to the container |
| `--force` | rewrite targets even when up to date | off |
| `MM_JOBS=N` | same as `--jobs`, for the wrapper | |
| `MEDIAMILL_IMAGE` | image the wrapper runs | `ghcr.io/gidw/mediamill:latest` |

Exit codes: `0` success, `1` usage or input error, `2` finished but one or more files failed (see the `FAIL` lines).

Output lines: `JPG`, `MP4`, `CP` and `SKIP` per file on stdout; `FAIL <file>: <reason>` on stderr.

## Platform notes

**macOS (podman machine).** Input and output paths must be under `/Users`, `/private` or `/var/folders`, the only directories the VM shares with the host. `/tmp` is a symlink to `/private/tmp`, so use the latter. Parallelism is capped by the CPUs assigned to the machine (`podman machine inspect`). Output files are owned by you.

**Linux (rootless podman).** The container user is mapped onto you with `--userns=keep-id:uid=65532,gid=65532` and your supplementary groups are kept with `--group-add keep-groups`, so output written to a group-shared directory (for example a `media` group) gets your user and that group. `keep-groups` requires the `crun` runtime.

## Without the wrapper

The wrapper only assembles a `podman run`. The equivalent by hand:

```sh
podman run --rm -it --init \
  --userns=keep-id:uid=65532,gid=65532 \
  -v /path/to/input:/in:ro \
  -v /path/to/output:/out \
  ghcr.io/gidw/mediamill:latest --jobs 4 /in /out
```

Inside the image the tool is `/usr/local/bin/mediamill`; `/in` is the read-only input, `/out` the writable output and working directory.

## Development

```sh
podman build -t localhost/mediamill:dev .          # builds libvips against mozjpeg; the build fails if that linkage is lost
test/worker.test.sh                                # per-file worker: naming, collisions, skip/force, failure and signal cleanup
test/compare.sh native                             # golden test: byte-identical to the legacy script (needs Homebrew vips with mozjpeg + ffmpeg)
test/compare.sh container localhost/mediamill:dev  # same, running the tool inside the image
```

CI builds both architectures on native runners, smoke-tests the pushed image, scans it with Trivy and rebuilds weekly. Renovate keeps the pinned mozjpeg, libvips, ffmpeg and action versions current.

## License

MIT (see `LICENSE`) for the code in this repository. The published image also bundles third-party software under its own licences: libvips (LGPL-2.1-or-later), mozjpeg (BSD-style), and a static ffmpeg build that includes libx264 (GPL).
