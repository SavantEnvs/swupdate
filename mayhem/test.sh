#!/usr/bin/env bash
#
# mayhem/test.sh — RUN upstream's cmocka suite (built by mayhem/build.sh with test_defconfig, normal flags).
# Each binary prints TAP; we require every binary to exist, exit 0 and report exactly the expected plan
# with every case "ok", so a binary neutered into exit(0) (no TAP) or a skipped/removed case fails here.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

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

BUILD="$SRC/mayhem/build-test"
# binary:expected number of cases (test_stream_interface prints no TAP, so it is not part of the oracle)
SUITES="test_cpio_utils:14 test_crypt:4 test_flash_handler:41 test_handlers:9 test_hash:2 test_installer:8
test_mongoose_upload:1 test_network_ipc_if:2 test_network_thread:12 test_parser:18 test_progress_thread:6
test_util:11 test_verify:7"

passed=0 failed=0 skipped=0
cd "$BUILD" || { echo "missing $BUILD: run mayhem/build.sh" >&2; emit_ctrf "cmocka" 0 1 0; exit 1; }
for s in $SUITES; do
  name="${s%%:*}" want="${s##*:}"
  if [ ! -x "test/$name" ]; then
    echo "MISSING test binary test/$name" >&2
    failed=$((failed + want)); continue
  fi
  out="$(LD_LIBRARY_PATH="$BUILD" CMOCKA_MESSAGE_OUTPUT=TAP SOFTHSM2_CONF=test/data/token/softhsm.conf \
         timeout 300 "test/$name" 2>&1)"
  rc=$?
  ok=$(printf '%s\n' "$out" | grep -Ec '^ok [0-9]+ ' || true)
  skip=$(printf '%s\n' "$out" | grep -Ec '^ok [0-9]+ .*# SKIP' || true)
  nok=$(printf '%s\n' "$out" | grep -Ec '^not ok [0-9]+ ' || true)
  plan=$(printf '%s\n' "$out" | grep -E '^1\.\.[0-9]+$' | head -1)
  ok=$((ok - skip))
  echo "$name: rc=$rc ok=$ok not_ok=$nok skip=$skip plan=${plan:-none} expected=1..$want"
  if [ "$rc" -ne 0 ] || [ "$plan" != "1..$want" ] || [ "$ok" -ne "$want" ] || [ "$nok" -ne 0 ]; then
    printf '%s\n' "$out" | tail -20 >&2
    # whatever did not pass counts as failed, so the total always reaches the expected number
    miss=$((want - ok - skip)); [ "$miss" -lt 1 ] && miss=1
    failed=$((failed + miss))
  fi
  passed=$((passed + ok)); skipped=$((skipped + skip))
done

emit_ctrf "cmocka" "$passed" "$failed" "$skipped"
