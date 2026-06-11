// P-VM.2 abort-path differential: an INVALID ARG to a static call aborts the
// call (evalStaticCall checks per-arg, unlike evalCall) and the invalid
// becomes the statement result -> program stops at the statement boundary.
// Note puts(twice(missing)) would NOT abort: the invalid would flow into
// puts and print -- the `let` binding makes it a statement-level invalid.
def twice(x) { return x * 2; }
puts("before");
let r = twice(missing_global);
puts("never-reached:" + r);
