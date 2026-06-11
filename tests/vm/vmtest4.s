// P-VM.2 differential test: arrays, maps, index get/store, static calls,
// block-scoped lets. Redefined defs (counts!=1) defeat static promotion so
// vmCompileFunc compiles those bodies; single defs (twice) stay promoted so
// their call sites emit nkStaticCall (vmOpStaticCall) and their declaration
// compiles to vmOpMakeStaticFn.

// promoted def -> nkStaticCall at every call site
def twice(x) { return x * 2; }

// func chunk containing vmOpStaticCall
def usetwice(a) { return twice(a) + twice(a + 1); }
def usetwice(a) { twice(a) + twice(a + 1); }

// func chunk with array/map literals, index reads/writes, nested stores
// (the parser only accepts single-level `name[idx] = value`; nested stores
// go through a reference temp, which still exercises chained nkIndex reads)
def coll(n) {
    let arr = [1, 2, 3];
    arr[0] = arr[1] + n;
    let m = {"a": 1, "b": {"c": 2}};
    let inner = m["b"];
    inner["c"] = m["a"] + 10;
    m["new"] = arr;
    return "" + arr[0] + ":" + m["b"]["c"] + ":" + m["new"][2];
}
def coll(n) {
    let arr = [1, 2, 3];
    arr[0] = arr[1] + n;
    let m = {"a": 1, "b": {"c": 2}};
    let inner = m["b"];
    inner["c"] = m["a"] + 10;
    m["new"] = arr;
    "" + arr[0] + ":" + m["b"]["c"] + ":" + m["new"][2];
}

// func chunk with block-scoped lets: shadowing, re-let in same block,
// while-body fresh-per-iteration lets, param shadowing
def blocks(p) {
    let x = 1;
    if (p > 0) {
        let x = 100;
        x = x + p;
        puts("inner:" + x);
        let x = 999;
        puts("relet:" + x);
    }
    puts("outer:" + x);
    let i = 0;
    let acc = "";
    while (i < 3) {
        let y = i * 2;
        acc = acc + y + ",";
        i = i + 1;
    }
    puts("acc:" + acc);
    if (p > 0) {
        let p = p + 50;
        puts("shadowp:" + p);
    }
    puts("param:" + p);
    return x;
}
def blocks(p) {
    let x = 1;
    if (p > 0) {
        let x = 100;
        x = x + p;
        puts("inner2:" + x);
        let x = 999;
        puts("relet2:" + x);
    }
    puts("outer2:" + x);
    let i = 0;
    let acc = "";
    while (i < 3) {
        let y = i * 2;
        acc = acc + y + ",";
        i = i + 1;
    }
    puts("acc2:" + acc);
    if (p > 0) {
        let p = p + 50;
        puts("shadowp2:" + p);
    }
    puts("param2:" + p);
    x;
}

puts(twice(21));
puts(usetwice(5));
puts(coll(4));
puts(blocks(7));

// top-level VM coverage: array/map literals + index get/store chains
let garr = [10, 20, 30];
garr[1] = garr[2] + 5;
puts(garr[1]);
let gm = {"k": garr, "n": 1};
garr[0] = 99;
gm["n"] = gm["n"] + gm["k"][0];
puts(gm["n"]);
puts(len(gm["k"]));

// invalid flows INTO a lib call unchecked (evalCall has no arg check):
// the aborted static call's invalid is printed by puts, program continues
puts(twice(missing_global));
puts("after-invalid-print");

