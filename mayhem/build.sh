#!/usr/bin/env bash
#
# mayhem/build.sh — builds swupdate twice (Kbuild, out of tree under mayhem/build-*):
#   build-test: upstream's test_defconfig with normal flags, plus its cmocka suite binaries (run by test.sh)
#   build-fuzz: the same config with the sanitizers, DWARF 3 and SanCov on every object, XZ/ZSTD/LZ4 on,
#               linked into one libFuzzer binary + one -standalone reproducer per harness
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
TESTDIR="$SRC/mayhem/build-test"
FUZZDIR="$SRC/mayhem/build-fuzz"
rm -rf "$TESTDIR" "$FUZZDIR"
mkdir -p "$TESTDIR" "$FUZZDIR"

# 1) test suite: upstream's own flags (test_defconfig), nothing sanitized
make O="$TESTDIR" test_defconfig
if [ -n "$COVERAGE_FLAGS" ]; then
  sed -i "s|^CONFIG_EXTRA_CFLAGS=.*|CONFIG_EXTRA_CFLAGS=\"-g $COVERAGE_FLAGS\"|" "$TESTDIR/.config"
  echo "CONFIG_EXTRA_LDFLAGS=\"$COVERAGE_FLAGS\"" >> "$TESTDIR/.config"
  make O="$TESTDIR" olddefconfig
fi
make O="$TESTDIR" -j"$MAYHEM_JOBS"
# builds the test binaries; EXECUTE_TEST=true skips running them (test.sh does that)
make O="$TESTDIR" test EXECUTE_TEST=true
# test_verify reads RSA test keys that the Makefile generates and then deletes as intermediates
(cd "$TESTDIR" && openssl genrsa -out test/data/signing-secret.pem 2>/dev/null \
  && openssl dgst -sha256 -sign test/data/signing-secret.pem -out test/data/signature test/data/to-be-signed \
  && openssl rsa -in test/data/signing-secret.pem -out test/data/signing-pubkey.pem -outform PEM -pubout 2>/dev/null \
  && rm test/data/signing-secret.pem)

# 2) the fuzzed code: same config, every object sanitized, DWARF 3, SanCov, plus the compressors
make O="$FUZZDIR" test_defconfig
sed -i \
  -e "s|^CONFIG_EXTRA_CFLAGS=.*|CONFIG_EXTRA_CFLAGS=\"$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link\"|" \
  -e 's|^# CONFIG_XZ is not set|CONFIG_XZ=y|' \
  -e 's|^# CONFIG_ZSTD is not set|CONFIG_ZSTD=y|' \
  -e 's|^# CONFIG_LZ4 is not set|CONFIG_LZ4=y|' \
  "$FUZZDIR/.config"
make O="$FUZZDIR" olddefconfig
make O="$FUZZDIR" -j"$MAYHEM_JOBS"

# swupdate's own main() lives in core/built-in.o: rename it so the fuzz engine's main wins
objcopy --redefine-sym main=swupdate_main "$FUZZDIR/core/built-in.o" "$FUZZDIR/core/built-in-nomain.o"

cd "$FUZZDIR"
SWOBJS="core/built-in-nomain.o handlers/built-in.o bootloader/built-in.o suricatta/built-in.o crypto/built-in.o ipc/built-in.o"
SWLIBS="corelib/lib.a mongoose/lib.a lws/lib.a parser/lib.a fs/lib.a containers/lib.a"
LDLIBS="-lpthread -lubootenv -ljson-c -llua5.4 -lcurl -lconfig -larchive -lcrypto -lssl -lubi -lmtd -lz -lzmq -llzma -lzstd -llz4"
INCLUDES="-Iinclude -I$SRC/include -include include/generated/autoconf.h -I/usr/include/lua5.4"
HARNESS_FLAGS="-std=gnu99 -D_GNU_SOURCE -DNDEBUG $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link"

$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -x c -c "$STANDALONE_FUZZ_MAIN" -o standalone_main.o

# <target>:<source>:<extra cflags>
for spec in \
  "fuzz_swd_libconfig:fuzz_swd.c:" \
  "fuzz_swd_json:fuzz_swd.c:-DSWD_JSON" \
  "fuzz_cpio_header:fuzz_cpio_header.c:" \
  "fuzz_semver:fuzz_semver.c:" \
  "fuzz_copyfile:fuzz_copyfile.c:"; do
  IFS=: read -r name file extra <<<"$spec"
  # shellcheck disable=SC2086
  $CC $HARNESS_FLAGS $extra $INCLUDES -c "$SRC/mayhem/$file" -o "$name.o"
  # shellcheck disable=SC2086
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$name.o" lsan_off.o $SWOBJS $SWLIBS $LDLIBS -Wl,-E \
    -o "$SRC/$name"
  # shellcheck disable=SC2086
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "$name.o" standalone_main.o lsan_off.o $SWOBJS $SWLIBS $LDLIBS -Wl,-E \
    -o "$SRC/$name-standalone"
done
