# mediamill — libvips compiled against mozjpeg (distro libvips links libjpeg-turbo and
# silently drops trellis-quant/optimize-scans/quant-table), static ffmpeg, zsh scripts.
# Build: podman build -t localhost/mediamill:dev .

# Sources are verified before use: mozjpeg by the commit its tag points to (GitHub's generated
# tag archives are not byte-stable), libvips by the sha256 of its uploaded release tarball.
# Renovate updates each tag together with its digest (see renovate.json).
# renovate-digest: datasource=github-tags depName=mozilla/mozjpeg
ARG MOZJPEG_TAG=v4.1.5
ARG MOZJPEG_COMMIT=6c9f0897afa1c2738d7222a0a9ab49e8b536a267
# renovate-digest: datasource=github-release-attachments depName=libvips/libvips
ARG VIPS_TAG=v8.18.7
ARG VIPS_SHA256=5baaead3b0bb20ffdb9e9ff09aa9fda08620923df77b63b436654cb5e0b3bf94

FROM docker.io/mwader/static-ffmpeg:9.0.1 AS ffmpeg

# ── builder ───────────────────────────────────────────────────────────────────
FROM docker.io/library/debian:trixie-slim AS builder
ARG MOZJPEG_TAG
ARG MOZJPEG_COMMIT
ARG VIPS_TAG
ARG VIPS_SHA256
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git build-essential cmake nasm meson ninja-build pkgconf \
      libglib2.0-dev libexpat1-dev libheif-dev libpng-dev libwebp-dev \
      libopenjp2-7-dev libexif-dev liblcms2-dev libhwy-dev \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
# mozjpeg: libjpeg62 ABI + encoder extensions. LIBDIR must be absolute (relative → installs into cwd).
RUN git -c advice.detachedHead=false clone --quiet --depth 1 --branch "${MOZJPEG_TAG}" https://github.com/mozilla/mozjpeg.git mozjpeg \
 && test "$(git -C mozjpeg rev-parse HEAD)" = "${MOZJPEG_COMMIT}" \
 && cmake -S mozjpeg -B mozjpeg-build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_INSTALL_LIBDIR=/usr/local/lib \
      -DENABLE_STATIC=0 -DPNG_SUPPORTED=0 -DWITH_TURBOJPEG=0 \
 && ninja -C mozjpeg-build install
ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
# libvips: only the loaders the tool needs; modules disabled so everything is in libvips.so.
RUN curl -fsSL -o vips.tar.xz "https://github.com/libvips/libvips/releases/download/${VIPS_TAG}/vips-${VIPS_TAG#v}.tar.xz" \
 && echo "${VIPS_SHA256}  vips.tar.xz" | sha256sum -c - \
 && tar xJf vips.tar.xz && cd "vips-${VIPS_TAG#v}" \
 && meson setup build --prefix=/usr/local --libdir=lib --buildtype=release \
      -Ddeprecated=false -Dexamples=false -Dcplusplus=false -Ddocs=false \
      -Dmodules=disabled -Dintrospection=disabled -Dvapi=false \
      -Djpeg=enabled -Dpng=enabled -Dwebp=enabled -Dheif=enabled -Dopenjpeg=enabled \
      -Dexif=enabled -Dlcms=enabled -Dhighway=enabled \
      -Dcgif=disabled -Dimagequant=disabled -Dquantizr=disabled -Dspng=disabled -Dorc=disabled \
      -Dmagick=disabled -Dpoppler=disabled -Drsvg=disabled -Dtiff=disabled -Dpangocairo=disabled \
      -Dfontconfig=disabled -Dopenslide=disabled -Dmatio=disabled -Dcfitsio=disabled -Dfftw=disabled \
      -Dopenexr=disabled -Djpeg-xl=disabled -Dpdfium=disabled -Dnifti=disabled -Duhdr=disabled -Darchive=disabled \
 && meson compile -C build && meson install -C build \
 && grep -q '^#define HAVE_JPEG_EXT_PARAMS' build/config.h   # build fails if mozjpeg extensions were not detected

# ── runtime ───────────────────────────────────────────────────────────────────
FROM docker.io/library/debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      zsh findutils coreutils poppler-utils \
      libglib2.0-0t64 libexpat1 libheif1 libheif-plugin-libde265 libheif-plugin-dav1d \
      libpng16-16t64 libwebp7 libwebpmux3 libwebpdemux2 libopenjp2-7 libexif12 liblcms2-2 libhwy1t64 \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd -g 65532 app && useradd -M -u 65532 -g 65532 -d /out -s /usr/sbin/nologin app \
 && mkdir -p /in /out && chown 65532:65532 /out
COPY --from=builder /usr/local/lib /usr/local/lib
# vipsheader: used by the tests CI runs inside the image, and handy for inspecting output
COPY --from=builder /usr/local/bin/vips /usr/local/bin/vipsheader /usr/local/bin/
# ffprobe is not used by the tool; each static binary is ~105 MB
COPY --from=ffmpeg  /ffmpeg /usr/local/bin/ffmpeg
# Search order is enforced by 00-usr-local.conf (sorts before libc.conf and the multiarch conf, so
# /usr/local/lib wins on every arch) and verified by the ldd assertion: libjpeg.so.62 must resolve to mozjpeg.
RUN echo /usr/local/lib > /etc/ld.so.conf.d/00-usr-local.conf \
 && ldconfig \
 && ldd /usr/local/lib/libvips.so.42 | grep -q 'libjpeg.so.62 => /usr/local/lib/' \
 && /usr/local/bin/vips --version && /usr/local/bin/ffmpeg -version | head -1 && /usr/bin/pdfimages -v 2>&1 | head -1
COPY libexec/mediamill libexec/mediamill-worker libexec/mediamill-lib.zsh /usr/local/bin/

ARG VERSION=0.0.0
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="mediamill" \
      org.opencontainers.image.source="https://github.com/GiDW/mediamill" \
      org.opencontainers.image.description="Batch image -> optimised JPEG (libvips+mozjpeg), gif -> mp4 (ffmpeg)" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.licenses="MIT"

ENV MM_VIPS=/usr/local/bin/vips MM_FFMPEG=/usr/local/bin/ffmpeg MM_PDFIMAGES=/usr/bin/pdfimages
VOLUME ["/in", "/out"]
WORKDIR /out
USER 65532:65532
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/mediamill"]
CMD ["--help"]
