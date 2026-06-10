// Abort-path differential: undefined-variable read inside a VM-compiled
// function chunk propagates invalid up and stops the program.
def boom(x) { return x + missing_global; }
def boom(x) { x + missing_global; }
puts("before");
puts(boom(1));
puts("never-reached");
