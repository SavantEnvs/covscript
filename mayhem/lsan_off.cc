/* Build-time LeakSanitizer off-switch for the sanitized CovScript interpreter (`cs`).
 *
 * `cs` is a run-once-per-input batch tool: it lexes, parses, code-generates and then
 * interprets a single script file and exits. Teardown is deliberately skipped on the way out.
 * sources/covscript.cpp's process_context::on_process_exit_default_handler drains the call
 * stack and then calls std::exit() outright — its in-tree comment says so plainly ("Pools not
 * collected here (live callables reference them); std::exit reclaims everything") — and the
 * compiler's per-unit token arenas plus the generated statement tree are likewise still live
 * when the process goes away. Under leak detection those benign at-exit allocations are
 * reported on essentially EVERY input, valid scripts included, which would bury the real
 * memory-safety bugs (out-of-bounds / use-after-free in the lexer, parser, codegen and
 * runtime) that Mayhem is here to find.
 *
 * -fsanitize=address always bundles LeakSanitizer in and there is no flag that keeps ASan while
 * dropping just the leak checks, so this TU is compiled with $SANITIZER_FLAGS and linked into
 * the fuzz binary by mayhem/build.sh. ASan's heap/stack/global out-of-bounds and use-after-free
 * checks and all of UBSan stay ON and halting; only leak REPORTING is suppressed. Nothing here
 * touches the runtime option set, and the harness never carries a compiled-in override of the
 * sanitizer option strings — Mayhem alone owns those.
 */
extern "C" int __lsan_is_turned_off() { return 1; }
