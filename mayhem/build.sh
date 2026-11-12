#!/usr/bin/env bash
#
# mayhem/build.sh — build txiki.js' fuzz harnesses (sanitized, instrumented) and its `tjs` CLI for the
# functional oracle (normal flags). Runs as `mayhem` in /mayhem; re-runnable and air-gapped.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS STANDALONE_FUZZ_MAIN

cd "$SRC"

# 0) The six git submodules are empty in a plain checkout. Populate each from the pinned copy baked into
#    the image (a nested git repo: upstream's CMake `git apply`s its carried patches into mbedtls and
#    libwebsockets). A checkout that already has them (CI uses submodules: recursive) is left alone.
for name in libuv quickjs mimalloc wamr mbedtls libwebsockets; do
  if [ -z "$(ls -A "deps/$name" 2>/dev/null)" ]; then
    sha="$(git ls-tree HEAD "deps/$name" | awk '{print $3}')"
    src="/opt/toolchains/deps/$name-${sha:0:12}/src"
    [ -n "$sha" ] && [ -d "$src" ] || { echo "build.sh: no pinned source for deps/$name (gitlink '$sha')" >&2; exit 1; }
    mkdir -p "deps/$name"
    cp -a --no-preserve=ownership "$src/." "deps/$name/"
  fi
done

# Always configure from scratch: the image build resolves `clang` through the ccache masquerade dir and
# a later plain re-run resolves it to /usr/bin/clang; CMake then sees a changed CMAKE_C_COMPILER, wipes
# the cache and drops every -D (re-enabling FFI). Both build dirs are gitignored upstream.
rm -rf build-oracle build-fuzz
# Upstream's own switches; libffi is not needed by any harness or by the oracle.
# WAMR's SIMD support FetchContents simde at configure time: point it at the pinned in-image copy.
COMMON_CMAKE=(-G Ninja -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" -DBUILD_WITH_FFI=OFF
              -DFETCHCONTENT_SOURCE_DIR_SIMDE=/opt/toolchains/deps/simde-0.8.2/src
              -DFETCHCONTENT_FULLY_DISCONNECTED=ON)

# 1) The functional-oracle build: upstream's normal Release flags, no sanitizers, no DWARF pin.
#    Output: build-oracle/tjs (build-*/ is gitignored upstream).
cmake -S . -B build-oracle "${COMMON_CMAKE[@]}" -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS"
cmake --build build-oracle --target tjs-cli -j"$MAYHEM_JOBS"

# 2) The sanitized fuzz build. Everything linked into the harnesses is built with $SANITIZER_FLAGS,
#    $DEBUG_FLAGS and SanCov (-fsanitize=fuzzer-no-link) so the fuzzed code (tjs, QuickJS, WAMR,
#    ada, mbedtls, miniz, ...) is instrumented. mayhem/lsan_off.cc (the build-time LSan-off hook) is
#    added as a direct source of every harness executable by mayhem/CMakeLists.txt. mimalloc stays off (it cannot be combined with ASan,
#    upstream's own rule). Release is avoided on purpose: it would add -DNDEBUG.
FUZZ_CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link"
case "$SANITIZER_FLAGS" in
  *address*)
    # Upstream's BUILD_WITH_ASAN settings: TJS__HAS_ASAN disables WAMR's native stack-boundary check,
    # which ASan's fake stacks break.
    FUZZ_CFLAGS="$FUZZ_CFLAGS -DTJS__HAS_ASAN -fsanitize-address-use-after-return=never" ;;
esac
cmake -S mayhem -B build-fuzz "${COMMON_CMAKE[@]}" -DCMAKE_BUILD_TYPE=Fuzz \
      -DCMAKE_C_FLAGS="$FUZZ_CFLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_CFLAGS" \
      -DCMAKE_C_FLAGS_FUZZ=-O1 -DCMAKE_CXX_FLAGS_FUZZ=-O1
TARGETS=(wasm url webcrypto text inflate js)
EXES=()
for t in "${TARGETS[@]}"; do EXES+=("fuzz_${t}_fuzz" "fuzz_${t}_standalone"); done
cmake --build build-fuzz --target "${EXES[@]}" -j"$MAYHEM_JOBS"

for t in "${TARGETS[@]}"; do
  cp -f "build-fuzz/out/fuzz_$t" "/mayhem/fuzz_$t"
  cp -f "build-fuzz/out/fuzz_$t-standalone" "/mayhem/fuzz_$t-standalone"
done
