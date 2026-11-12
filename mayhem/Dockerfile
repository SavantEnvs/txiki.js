# syntax=docker/dockerfile:1.7
#
# Commit image for txiki.js, on top of the org C/C++ base. The six git submodules (deps/libuv,
# quickjs, mimalloc, wamr, mbedtls, libwebsockets) are empty in a plain checkout, so they are
# pre-fetched at their pinned gitlink commits into /opt/toolchains/deps/<name>-<sha12>/src and
# build.sh copies them (as nested git repos, which upstream's `git apply` patch step needs) into deps/.
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

USER root
# Each entry is fetched at the exact commit recorded in the txiki.js tree (gitlink) or named by the
# dependency's own build (simde v0.8.2, which WAMR's CMake would otherwise FetchContent at configure
# time; mbedtls-framework, mbedtls' own submodule that its scripts/config.py needs).
RUN set -e; \
    fetch() { \
      mkdir -p "$1"; cd "$1"; \
      git init -q .; git remote add origin "$2"; \
      git fetch -q --depth 1 origin "$3"; git checkout -q FETCH_HEAD; \
      [ "$(git rev-parse HEAD)" = "$3" ]; \
    }; \
    D=/opt/toolchains/deps; \
    fetch $D/libuv-dd9f081cc55a/src         https://github.com/libuv/libuv                              dd9f081cc55a4d83e2a976848d074f28ee5f34eb; \
    fetch $D/quickjs-7b5f588e0f9b/src       https://github.com/quickjs-ng/quickjs.git                   7b5f588e0f9b643e2996f291bfc861abeaceddc2; \
    fetch $D/mimalloc-a5969c54000f/src      https://github.com/microsoft/mimalloc                       a5969c54000f44cd45968e830f6482592373cb0e; \
    fetch $D/wamr-8c18e3f68b16/src          https://github.com/bytecodealliance/wasm-micro-runtime.git  8c18e3f68b16c4bcaf05996b2636f6ed2b4cf629; \
    fetch $D/mbedtls-068ff080b369/src       https://github.com/Mbed-TLS/mbedtls                         068ff080b369adfac81509f9b57b2afabaf82dc5; \
    fetch $D/mbedtls-068ff080b369/src/framework https://github.com/Mbed-TLS/mbedtls-framework           dde0c4a0e448a0552f18817dcea633bb851fd288; \
    fetch $D/libwebsockets-5f39aa483715/src https://github.com/warmcat/libwebsockets                    5f39aa483715b813f4d85a692fcb361b5d8d0c1b; \
    fetch $D/simde-0.8.2/src                https://github.com/simd-everywhere/simde                    71fd833d9666141edcd1d3c109a80e228303d8d7; \
    chmod -R a+rX $D

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
