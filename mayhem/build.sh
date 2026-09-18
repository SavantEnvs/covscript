#!/usr/bin/env bash
#
# mayhem/build.sh — build the CovScript interpreter (fuzz target `cs`) and the
# upstream test suite. Runs inside the commit image as `mayhem` in /mayhem.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# CMake needs the third-party submodule (covscript-deps). A fresh CI checkout copies only
# the gitlink, so populate it on the FIRST build; once its files exist in the image the
# re-run skips this entirely, keeping the rebuild offline-idempotent.
if [ ! -e third-party/CMakeLists.txt ]; then
	git submodule update --init --recursive
fi

# 0) Build-time LSan opt-out (see mayhem/lsan_off.cc) — `cs` is an allocate-and-exit
#    interpreter that never frees its context/AST before exit, so LSan would flag a benign
#    leak on every input. Keep ASan bounds/UAF + UBSan fully on and halting.
"$CXX" $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o /tmp/lsan_off.o

# 1) Sanitized fuzz build of the interpreter itself (raw file-input target: cs @@).
#    The whole project (compiler + runtime) is instrumented with $SANITIZER_FLAGS,
#    and carries DWARF-3 debug info for Mayhem triage.
cmake -S . -B build-fuzz -G "Unix Makefiles" \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
      -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
      -DCMAKE_EXE_LINKER_FLAGS="/tmp/lsan_off.o"
cmake --build build-fuzz --target cs -j"$MAYHEM_JOBS"
cp build-fuzz/cs /mayhem/cs

# 2) Upstream test suite, built with the project's NORMAL flags (independent build)
#    so mayhem/test.sh only RUNS it:
#      - cs_unit_tests  (compiler unit tests: lexer/parser/trim_expr/translate)
#      - cs             (clean interpreter for the CI integration .csc tests)
cmake -S . -B build-tests -G "Unix Makefiles" -DCS_BUILD_TESTS=ON \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS"
cmake --build build-tests --target cs cs_unit_tests -j"$MAYHEM_JOBS"
