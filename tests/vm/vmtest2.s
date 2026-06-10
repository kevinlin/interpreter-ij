// Abort-path differential: calling a non-function stops the program at the
// statement boundary (invalid statement value), identically in both engines.
puts("before");
let notfn = 42;
let r = notfn(1);
puts("never-reached:" + r);
