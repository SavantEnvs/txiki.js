#!/usr/bin/env bash
#
# mayhem/test.sh — RUN txiki.js's own tests (selected deterministic files) + known-answer probes against build-oracle/tjs.
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}


TJS="$SRC/build-oracle/tjs"
passed=0; failed=0
pass() { passed=$((passed+1)); echo "PASS $1"; }
fail() { failed=$((failed+1)); echo "FAIL $1: ${2:-}" >&2; }

if [ ! -x "$TJS" ]; then
  fail "oracle-binary" "$TJS missing (mayhem/build.sh must build it)"
  emit_ctrf "txiki.js-tests" "$passed" "$failed" 0
  exit $?
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# kat <name> <expected> <js>: the program must print exactly <expected>
kat() {
  local name="$1" expect="$2" js="$3" out
  out="$(timeout 60 "$TJS" eval "$js" 2>"$WORK/err")"
  if [ "$out" = "$expect" ]; then pass "kat:$name"; else fail "kat:$name" "expected [$expect] got [$out] $(head -c 300 "$WORK/err")"; fi
}

kat sha256-abc "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" \
  "crypto.subtle.digest('SHA-256', new TextEncoder().encode('abc')).then(b => console.log([...new Uint8Array(b)].map(x => x.toString(16).padStart(2, '0')).join('')))"
kat hmac-sha256 "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8" \
  "crypto.subtle.importKey('raw', new TextEncoder().encode('key'), {name:'HMAC', hash:'SHA-256'}, false, ['sign']).then(k => crypto.subtle.sign('HMAC', k, new TextEncoder().encode('The quick brown fox jumps over the lazy dog'))).then(b => console.log([...new Uint8Array(b)].map(x => x.toString(16).padStart(2, '0')).join('')))"
kat url-parse "https://user:pw@example.com:8080/a/c?x=1#h|example.com:8080|/a/c|?x=1" \
  "const u = new URL('https://user:pw@example.com:8080/a/b/../c?x=1#h'); console.log([u.href, u.host, u.pathname, u.search].join('|'))"
kat url-base "http://example.com/foo/bar%20baz" \
  "console.log(new URL('bar baz', 'http://example.com/foo/x').href)"
kat urlsearchparams "a=1&b=x+y&a=3" \
  "const p = new URLSearchParams('a=1&b=x+y'); p.append('a', '3'); console.log(p.toString())"
kat text-encode "195,169,226,130,172" \
  "console.log(Array.from(new TextEncoder().encode('é€')).join(','))"
kat text-decode "€!" \
  "console.log(new TextDecoder().decode(new Uint8Array([0xe2, 0x82, 0xac, 0x21])))"
kat base64 "aGVsbG8=|hello" \
  "console.log(btoa('hello') + '|' + atob('aGVsbG8='))"
kat inflate-zlib "hello" \
  "const ds = new DecompressionStream('deflate'); const w = ds.writable.getWriter(); w.write(new Uint8Array([0x78,0x9c,0xcb,0x48,0xcd,0xc9,0xc9,0x07,0x00,0x06,0x2c,0x02,0x15])); w.close(); new Response(ds.readable).text().then(t => console.log(t))"
kat wasm-const42 "42" \
  "const m = new WebAssembly.Module(new Uint8Array([0,0x61,0x73,0x6d,1,0,0,0,1,5,1,0x60,0,1,0x7f,3,2,1,0,7,5,1,1,0x66,0,0,0x0a,6,1,4,0,0x41,0x2a,0x0b])); console.log(new WebAssembly.Instance(m).exports.f())"
kat json-parse "3|a,b" \
  "const o = JSON.parse('{\"a\":[1,2,3],\"b\":{\"c\":\"d\"}}'); console.log(o.a.length + '|' + Object.keys(o).join(','))"

# upstream test files, each wrapped so a marker proves the file really ran to completion
TESTS="hashing text-coding text-encode-into uuid structured-clone compression userinfo
wasm-i32 wasm-i64 wasm-f32 wasm-f64 wasm-global wasm-import promise-exec-order random builtin
import-json import-text self abort-controller
webcrypto-aes webcrypto-aes-ctr webcrypto-aes-kw webcrypto-ec webcrypto-ed25519 webcrypto-hmac
webcrypto-jwk webcrypto-kdf webcrypto-rsa webcrypto-wrap webcrypto-x25519"
for t in $TESTS; do
  f="tests/test-$t.js"
  if [ ! -f "$f" ]; then fail "test:$t" "missing $f"; continue; fi
  cat > "$WORK/run-$t.js" <<JS
await import('file://$SRC/$f');
console.log('TJS_TEST_DONE $t');
JS
  out="$(timeout 120 "$TJS" run "$WORK/run-$t.js" 2>"$WORK/err")"; rc=$?
  if [ $rc -eq 0 ] && printf '%s\n' "$out" | grep -qx "TJS_TEST_DONE $t"; then pass "test:$t"
  else fail "test:$t" "rc=$rc $(head -c 300 "$WORK/err")"; fi
done

emit_ctrf "txiki.js-tests" "$passed" "$failed" 0
