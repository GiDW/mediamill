# AGENTS.md

mediamill converts a tree of images to optimised JPEG (libvips built against mozjpeg), GIFs to MP4 (ffmpeg), and copies everything else. It ships as a container image, `ghcr.io/gidw/mediamill`. `README.md` is the user documentation; this file is for working on the code.

## Layout

| Path | What it is |
|---|---|
| `bin/mediamill` | Host wrapper, the only thing users run. Builds a `podman run` with the right mounts and user mapping, then `exec`s it. |
| `libexec/mediamill` | Dispatcher, runs **inside the image** (`/usr/local/bin/mediamill`). Option parsing, single-file / PDF / directory modes, clash preflight, `xargs -P` fan-out. |
| `libexec/mediamill-worker` | Converts one file. Temp file + rename, skip when up to date, `FAIL` on stderr. |
| `libexec/mediamill-lib.zsh` | Shared by dispatcher and worker: which extensions are images/videos and what their target name is. |
| `test/*.test.sh` | Test suites; CI runs every file matching this pattern. |
| `test/make-corpus.sh` | Synthetic corpus for the CI smoke test. |
| `test/fixtures/` | Small committed inputs (EXIF-rotated, Display P3, HEIC, animated GIF, PDF). |
| `Containerfile` | Builds mozjpeg and libvips from verified sources, runtime on debian trixie-slim. |
| `.github/workflows/build.yml` | Entry point: triggers, per-event permissions, concurrency. |
| `.github/workflows/image.yml` | Reusable workflow with the actual jobs: native amd64/arm64 builds, smoke test, test suites, manifest merge. |

The libexec scripts are not meant to run on the host: without the image's vips they fail, or they silently use a non-mozjpeg vips.

## Testing

Do not install vips, ffmpeg or poppler on the host. Build the image and run the tests inside it; that is also what CI does:

```sh
podman build -t localhost/mediamill:dev .
for t in test/*.test.sh; do podman run --rm -v "$PWD:/repo:ro" --entrypoint zsh localhost/mediamill:dev "/repo/$t" || break; done
```

- `clash`, `cli`, `wrapper` and `syntax` need only zsh and also run directly on the host. `worker` and `pdf` need the image.
- Each suite prints `ok`/`FAIL` lines and ends with `failures: N`; the exit code is non-zero on any failure.
- Use podman for any other tool too (actionlint: `podman run --rm -v "$PWD:/repo:ro" -w /repo docker.io/rhysd/actionlint:latest -no-color`).
- On macOS, podman machine only shares `/Users`, `/private` and `/var/folders`. Mount from `/private/tmp` or `mktemp -d`, never `/tmp`.
- A new test file must be named `test/<name>.test.sh`, use the existing `assert` pattern and exit non-zero on failure; CI then runs it automatically.
- When adding a check, also confirm it fails when the behaviour is broken (mutate a copy of the script), not only that it passes.

## Code conventions

- zsh throughout, `set -u`, and `print -r --` for anything that echoes a path or user input.
- File names can contain any byte except NUL and `/`: pass lists NUL-separated (`find -print0`, `${(0)...}`, `print -rN`, `xargs -0`), never word-split them.
- Scripts must work with both GNU and BSD userland (tests also run on macOS): no `--` before the command in `xargs`, `zstat` instead of `stat`.
- Library functions in `mediamill-lib.zsh` return results in `$REPLY` instead of printing, so callers don't fork a subshell per file.
- The signal handling in `libexec/mediamill` (ignore INT/TERM, `kill -TERM 0`, background pipeline plus `wait`) and the worker's cleanup trap are deliberate; the comments explain why. Do not simplify them.
- One source maps to one output. The dispatcher's clash preflight rejects collisions before anything is written; the worker never renames.

### Output contract (documented in README; keep code, tests and README in sync)

- stdout: `JPG`, `MP4`, `CP`, `SKIP`, `RAW` per file, `PDF <file>: <n> images`. `--quiet` means nothing at all on stdout.
- stderr: `FAIL <file>: <reason>` and `CLASH <output> <- <sources>`.
- Exit codes: `0` ok, `1` usage or input error, `2` one or more files failed, `3` output name clash (nothing written).
- Changing `MM_VIPS_OPTS` or the vips/ffmpeg invocation changes output bytes for every user. `worker.test.sh` checks that the mozjpeg options take effect; keep that passing.

## Containerfile and dependencies

- Source dependencies are pinned as three lines: a `# renovate-digest:` comment, the tag ARG, then the digest ARG (commit SHA or tarball sha256). The regex in `renovate.json` depends on that exact layout. Update tag and digest together; never drop the verification (`rev-parse HEAD` check, `sha256sum -c`).
- Base images stay on tags on purpose, so the weekly no-cache rebuild picks up Debian security fixes.
- `.containerignore` is a whitelist (`*` then `!libexec/`). A new file the image needs must be added there.
- The build asserts that libvips detected mozjpeg's extensions (`HAVE_JPEG_EXT_PARAMS`) and that `libjpeg.so.62` resolves to `/usr/local/lib`. Keep both assertions.

## CI

- `build.yml` sets `permissions: {}` and grants per job: pull requests get a read-only token, only `publish` gets `packages: write`. `image.yml` has no permissions block on purpose: it inherits exactly what the caller grants.
- Actions are pinned to commit SHAs with a `# vN` comment; Renovate maintains them. Pin new actions the same way.
- Run actionlint after editing a workflow.

## Commits and docs

- Conventional commit subjects with an optional scope: `feat`, `fix`, `test`, `ci`, `build`, `refactor`, `docs`, `chore` (for example `fix(image): ...`). The body explains why.
- Update `README.md` in the same commit when user-visible behaviour, options, output lines, exit codes or the test list change.
- `VERSION` becomes the published image tag. Do not bump it unless asked.
- Do not commit or push unless asked.
