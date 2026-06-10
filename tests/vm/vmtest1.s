// P-VM.1 differential test: function chunks + top-level VM subset.
// Every def is REDEFINED so counts!=1 defeats static promotion -> no
// staticImpl -> vmCompileFunc actually compiles these bodies.
def add(a, b) { return a + b; }
def add(a, b) { a + b; }
def fib(n) { if (n < 2) { return n; } return fib(n - 1) + fib(n - 2); }
def fib(n) { if (n < 2) { return n; } fib(n - 1) + fib(n - 2); }
def mixed(a) { let d = a / 2.0; return d * 3; }
def mixed(a) { let d = a / 2.0; d * 3; }
def side(x) { puts("side:" + x); return x; }
def side(x) { puts("side:" + x); x; }
def shortcirc(a, b) { return (a && side(b)) || side(b + 1); }
def shortcirc(a, b) { (a && side(b)) || side(b + 1); }
def arity(a, b, c) { puts("arity:" + a + "," + b + "," + c); }
def arity(a, b, c) { puts("arity2:" + a + "," + b + "," + c); }
def bails(n) { let arr = [1, 2, 3]; return arr[n]; }
def bails(n) { let arr = [1, 2, 3]; arr[n]; }
def whileloop(n) { let s = 0; let i = 0; while (i < n) { s = s + i; i = i + 1; } return s; }
def whileloop(n) { let s = 0; let i = 0; while (i < n) { s = s + i; i = i + 1; } s; }
def neg(x) { return -x; }
def neg(x) { -x; }
def notf(x) { return !x; }
def notf(x) { !x; }
def cmps(a, b) { puts("" + (a < b) + (a <= b) + (a > b) + (a >= b) + (a == b) + (a != b) + (a % b)); }
def cmps(a, b) { puts("c2:" + (a < b) + (a <= b) + (a > b) + (a >= b) + (a == b) + (a != b) + (a % b)); }

puts(add(2, 3));
puts(fib(15));
puts(mixed(7));
puts(shortcirc(false, 10));
puts(shortcirc(true, 20));
arity(1, 2, 3, 4);
arity(1, 2);
puts(bails(1));
puts(whileloop(10));
puts(neg(5));
puts(notf(false));
cmps(3, 7);
cmps(7.5, 7.5);

// override pattern on a VM-compiled def
let oldAdd = add;
def add(a, b) { return oldAdd(a, b) * 10; }
puts(add(2, 3));

// top-level VM subset: while/if over global lets
let i = 0;
let acc = "";
while (i < 5) { acc = acc + i; i = i + 1; }
puts(acc);
if (acc == "01234") { puts("topif-ok"); } else { puts("topif-bad"); }
if (acc == "x") { puts("a"); } else { if (acc != "y") { puts("elseif-ok"); } }
puts("done");
