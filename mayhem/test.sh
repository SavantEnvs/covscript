#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the upstream test suite that mayhem/build.sh produced:
#   1. unit_tests/cs_unit_tests — the compiler unit tests (lexer/parser/trim_expr/translate),
#      exactly what upstream CI (.github/workflows/build.yml) runs.
#   2. The integration .csc tests upstream CI runs, asserted on their printed OUTPUT
#      (not just exit status), plus the `cs -v` version banner.
# Emits a CTRF report and exits non-zero iff any test failed.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
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

UNIT=build-tests/unit_tests/cs_unit_tests
CS=build-tests/cs
[ -x "$UNIT" ] || { echo "FATAL: $UNIT missing — build.sh must build it"; emit_ctrf cs-tests 0 1; exit 1; }
[ -x "$CS" ]   || { echo "FATAL: $CS missing — build.sh must build it";   emit_ctrf cs-tests 0 1; exit 1; }

passed=0; failed=0

# --- 1) compiler unit tests -------------------------------------------------
unit_out=$("$UNIT" 2>&1); unit_rc=$?
echo "$unit_out" | tail -5
unit_ran=$(echo "$unit_out"  | sed -n 's/.*\[==========\] \([0-9]\+\) tests ran\..*/\1/p' | tail -1)
unit_pass=$(echo "$unit_out" | sed -n 's/.*\[  PASSED  \] \([0-9]\+\) tests\..*/\1/p' | tail -1)
unit_fail=$(echo "$unit_out" | sed -n 's/.*\[  FAILED  \] \([0-9]\+\) tests\..*/\1/p' | tail -1)
unit_ran=${unit_ran:-0}; unit_pass=${unit_pass:-0}; unit_fail=${unit_fail:-0}
if [ "$unit_rc" -ne 0 ] || [ "$unit_ran" -lt 1 ] || [ "$unit_pass" -lt 1 ]; then
  # no parsable summary / nothing ran ⇒ the suite did not actually execute — hard fail
  echo "cs_unit_tests did not run correctly (rc=$unit_rc ran=$unit_ran passed=$unit_pass)"
  [ "$unit_fail" -ge 1 ] || unit_fail=1
fi
passed=$(( passed + unit_pass ))
failed=$(( failed + unit_fail ))

# --- 2) upstream CI integration tests (output-asserted) ----------------------
# check <name> <expected-substring> <cmd...>
check() {
  local name="$1" expect="$2"; shift 2
  local out
  out=$(timeout 300 "$@" 2>&1)
  if [ $? -eq 0 ] && printf '%s' "$out" | grep -qF "$expect"; then
    echo "PASS integration: $name"; passed=$((passed+1))
  else
    echo "FAIL integration: $name (expected output containing: $expect)"
    printf '%s\n' "$out" | tail -5
    failed=$((failed+1))
  fi
}

check version             "STD Version"                    "$CS" -v
check benchmark.csc       "Benchmark Finished"             "$CS" tests/benchmark.csc
check test_reentrant_co   "Body 0 exit"                    "$CS" tests/test_reentrant_co.csc
check test_dead_co.csc    "10"                             "$CS" tests/test_dead_co.csc
check struct_op.csc       "Call initializer: 1"            "$CS" tests/struct_op.csc
check inherit.csc         "Init base"                      "$CS" tests/inherit.csc

emit_ctrf cs-tests "$passed" "$failed" 0
