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

The first run pulls the image (about 90 MB compressed).

## Update

There are two parts to keep current: the wrapper function in your clone and the container image. Podman does not check for a newer `latest` on its own, so an update is always explicit:

```sh
git -C [CHOSEN_MEDIAMILL_PATH] pull
exec zsh                                        # reload the wrapper; or: source [CHOSEN_MEDIAMILL_PATH]/host/mediamill.zsh
podman pull ghcr.io/gidw/mediamill:latest
```

Usually only the image changes; pulling the clone is needed when `host/mediamill.zsh` changed (see `git log -- host/`). The image is rebuilt weekly with current base packages even when nothing in this repository changed, so `podman pull` alone is worth running now and then.

To check what you have, compare the image's version label with `VERSION` on the main branch:

```sh
podman image inspect ghcr.io/gidw/mediamill:latest --format '{{index .Config.Labels "org.opencontainers.image.version"}}'
```

To stay on a fixed version instead of `latest`, set `MEDIAMILL_IMAGE` in your `~/.zshrc`. Every push publishes a `<version>` tag (the contents of `VERSION`, for example `1.0.0`) and a `sha-<short commit>` tag; weekly rebuilds add a `YYYYMMDD` tag:

```sh
export MEDIAMILL_IMAGE=ghcr.io/gidw/mediamill:1.0.0
```

Old images are not removed by a pull. Reclaim the space with `podman image prune`.

## Usage

```
mediamill [--jobs N] [--force] [--quiet] <input-dir> <output-dir>
mediamill [--force] [--quiet] <image|gif> [<output-file>]
mediamill [--jobs N] [--force] [--quiet] [--extract-only] <file.pdf> [<out-dir>]
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

Silent unless something fails, for scripts and cron:

```sh
mediamill --quiet ~/Pictures/raw ~/Pictures/out || echo "some files failed"
```

### PDFs

When the input is a PDF, mediamill extracts the images embedded in it (`pdfimages -all`, native resolution and format), names them `0000.jpg`, `0001.jpg`, … in document order, and converts them like any folder. The output folder defaults to `./<stem>/` and is reused on re-runs, so an unchanged PDF is a no-op and a re-saved PDF is reconverted.

```sh
mediamill scans.pdf                 # -> ./scans/0000.jpg ...
mediamill scans.pdf ~/Pictures/scans
mediamill --extract-only scans.pdf raw/   # keep the extracted files as they are (png, jpg, ...)
```

`--extract-only` skips the optimisation step; the folder then holds the extracted files with lowercase extensions, overwritten on every run. Images `pdfimages` writes in formats mediamill does not convert (`.jb2`, `.ccitt`/`.params`, `.tif`) are kept unchanged in both modes. PDFs inside a directory tree are not extracted; they are copied like any other non-media file.

### Re-runs

A target that already exists and is newer than its source is skipped, so interrupting a run and starting it again continues where it stopped, and adding new files to the input converts only those. `--force` rewrites everything. Outputs whose source was removed are never deleted.

Files are written to a temporary name and renamed when complete, so a killed run leaves no half-written output. Ctrl-C stops all workers.

### Options and environment

| Option / variable | Meaning | Default |
|---|---|---|
| `--jobs N` | files converted in parallel | number of CPUs visible to the container |
| `--force` | rewrite targets even when up to date | off |
| `--quiet` | print nothing on stdout; failures still go to stderr and the exit code is unchanged | off |
| `--extract-only` | PDF input only: stop after extraction and rename, do not convert | off |
| `MM_JOBS=N` | same as `--jobs`, for the wrapper | |
| `MEDIAMILL_IMAGE` | image the wrapper runs | `ghcr.io/gidw/mediamill:latest` |

Exit codes: `0` success, `1` usage or input error, `2` finished but one or more files failed (see the `FAIL` lines).

Output lines: `JPG`, `MP4`, `CP` and `SKIP` per file on stdout, `RAW` per file with `--extract-only`, and `PDF <file>: <n> images` after a PDF; `FAIL <file>: <reason>` on stderr.

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
test/pdf.test.sh                                   # PDF input flow, natively (needs Homebrew poppler: brew install poppler)
test/compare.sh native                             # golden test: byte-identical to the legacy script (needs Homebrew vips with mozjpeg + ffmpeg)
test/compare.sh container localhost/mediamill:dev  # same, running the tool inside the image
```

CI builds both architectures on native runners, smoke-tests the pushed image, scans it with Trivy and rebuilds weekly. Renovate keeps the pinned mozjpeg, libvips, ffmpeg and action versions current.

## License

MIT (see `LICENSE`) for the code in this repository. The published image also bundles third-party software under its own licences: libvips (LGPL-2.1-or-later), mozjpeg (BSD-style), and a static ffmpeg build that includes libx264 (GPL).
