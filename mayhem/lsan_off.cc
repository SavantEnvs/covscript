// Build-time LeakSanitizer opt-out. `cs` is a run-once-per-input batch tool: it compiles +
// interprets a single script file and then exits without freeing its runtime context
// (cs::create_context) or the compiler's token/AST deques — a classic allocate-and-exit
// interpreter. Under LSan those benign process-exit leaks fire on essentially every input,
// drowning out the real memory-safety bugs (use-after-free / out-of-bounds in the lexer,
// parser, codegen and runtime) that Mayhem is meant to find. ASan's heap/stack/global
// out-of-bounds and use-after-free checks, and UBSan, stay fully on and halting.
extern "C" int __lsan_is_turned_off() { return 1; }
