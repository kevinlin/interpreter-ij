// P-VM.2 abort-path differential: index-assign to an INVALID collection
// short-circuits (no Put, idx/rhs never evaluated) and the invalid is the
// statement result -> program stops, identically in both engines.
def sideeffect(x) { puts("side:" + x); return x; }
puts("before");
missing_map[sideeffect(0)] = sideeffect(1);
puts("never-reached");
