// De-risk prototype for IMPLEMENTATION_PLAN.md Lever 3 (bytecode VM).
//
// WHY THIS EXISTS
// The P-B gate measured the incremental tree-walker arc at ~1.25x cumulative,
// well short of the 10x goal, and pivoted to a structural lever. Before paying
// the large, high-risk cost of lowering all ~19 IJ node kinds to bytecode
// inside src/interpreter.s (and re-proving the self-bootstrap fixed point), we
// need an EMPIRICAL speedup number for the VM lever. The spec only had a
// guessed "5-8x". This program measures it.
//
// WHAT IT COMPARES (apples-to-apples)
//   treeWalk : a faithful copy of interpreter.s's emitted Go runtime --
//              88-byte Value, Context{parent, map[string]Value} parent-chain
//              lookups, eval(*Node)(Value,bool) recursive dispatch with the
//              (Value,bool) return sentinel, FunctionCommand closure dispatch,
//              and a fresh *Context + params map + *ArrayValue per call. This
//              is the exact shape of the dominant `eval`+`Execute`+closure cost
//              in the stage2 pprof.
//   vm       : the SAME 88-byte Value, but compiled to bytecode with slot-based
//              locals on a reused value stack and a flat dispatch loop. Isolates
//              the Lever-3 win (kill per-node dispatch + per-call heap allocs)
//              WITHOUT also shrinking Value -- so it is a conservative lower
//              bound for the lever, not inflated by Lever-2 (NaN-box) gains.
//   vmLean   : Lever 3 + a leaner int64 stack, to show the combined ceiling if
//              Lever 2 is stacked on top later. Clearly separate from the
//              headline vm number.
//
// Workload: user-level recursive fib (arithmetic + comparison + function calls
// + if/return) -- the "arithmetic + function-call subset" the spec asks to
// prototype, and the CPU-bound recursion that the tree-walker pays the most for.
//
// HONESTY NOTE: this models the Go-side typed-AST tree-walk (what Lever 3
// replaces). It does NOT model the additional IJ-side MapValue "evaluate"
// string-lookup overhead of the deepest selfhost layer, which a real lowering
// would ALSO remove -- so the real-world lever is >= the number measured here.
package main

import (
	"fmt"
	"os"
	"runtime"
	"strconv"
	"time"
)

// ----------------------------------------------------------------------------
// Shared 88-byte Value (byte-for-byte the interpreter.s emit, src:4835).
// ----------------------------------------------------------------------------

const (
	tNull uint8 = iota
	tInt
	tDouble
	tString
	tBool
	tArray
	tMap
	tFunc
	tInvalid
)

type ArrayValue struct{ values []Value }
type MapValue struct{ pairs []Value } // stub; present only to match struct size
type Command interface{ isCommand() }

type Value struct {
	tag uint8
	b   bool
	i   int64
	d   float64
	s   string
	arr *ArrayValue
	m   *MapValue
	cmd Command
	inv string
}

func vInt(i int64) Value { return Value{tag: tInt, i: i} }
func vNull() Value       { return Value{tag: tNull} }
func vFunc(c Command) Value { return Value{tag: tFunc, cmd: c} }

func (v Value) IsTruthy() bool {
	switch v.tag {
	case tNull:
		return false
	case tInt:
		return v.i != 0
	case tBool:
		return v.b
	}
	return false
}

// Faithful to interpreter.s Value.Add / Subtract / LessThan (int paths).
func (v Value) Add(o Value) Value      { return Value{tag: tInt, i: v.i + o.i} }
func (v Value) Subtract(o Value) Value { return Value{tag: tInt, i: v.i - o.i} }
func (v Value) LessThan(o Value) Value { return Value{tag: tBool, b: v.i < o.i} }

// ----------------------------------------------------------------------------
// PART A: the tree-walker (faithful clone of the emitted runtime)
// ----------------------------------------------------------------------------

type Context struct {
	parent    *Context
	variables map[string]Value
}

func (c *Context) Get(name string) Value {
	for ctx := c; ctx != nil; ctx = ctx.parent {
		if v, ok := ctx.variables[name]; ok {
			return v
		}
	}
	return Value{tag: tInvalid, inv: "variable not found: " + name}
}
func (c *Context) Create(name string, value Value) Value {
	if c.variables == nil {
		c.variables = make(map[string]Value)
	}
	c.variables[name] = value
	return value
}

const (
	nkIntLit uint8 = iota
	nkIdent
	nkInfix
	nkIf
	nkReturn
	nkCall
	nkBlock
	nkFuncDecl
)

const (
	opAdd uint8 = iota
	opSub
	opLt
)

// Node mirrors the relevant fields of the emitted typed AST.
type Node struct {
	kind      uint8
	op        uint8
	iVal      int64
	name      string
	left      *Node
	right     *Node
	body      *Node
	list      []*Node
	params    []string
	hasLocals bool
}

type FunctionCommand struct {
	definitionCtx *Context
	executeFunc   func(*Context, *ArrayValue) Value
}

func (c *FunctionCommand) isCommand() {}
func (c *FunctionCommand) Execute(callerCtx *Context, params *ArrayValue) Value {
	return c.executeFunc(nil, params) // discards callerCtx, exactly like the emit
}

func eval(n *Node, ctx *Context) (Value, bool) {
	switch n.kind {
	case nkIntLit:
		return Value{tag: tInt, i: n.iVal}, false
	case nkIdent:
		return ctx.Get(n.name), false
	case nkInfix:
		return evalInfix(n, ctx)
	case nkIf:
		return evalIf(n, ctx)
	case nkReturn:
		return evalReturn(n, ctx)
	case nkCall:
		return evalCall(n, ctx)
	case nkBlock:
		return evalBlock(n, ctx)
	case nkFuncDecl:
		return evalFuncDecl(n, ctx)
	}
	return Value{tag: tInvalid, inv: "unknown node kind"}, false
}

func evalInfix(n *Node, ctx *Context) (Value, bool) {
	l, ret := eval(n.left, ctx)
	if ret {
		return l, true
	}
	if l.tag == tInvalid {
		return l, false
	}
	r, ret2 := eval(n.right, ctx)
	if ret2 {
		return r, true
	}
	if r.tag == tInvalid {
		return r, false
	}
	switch n.op {
	case opAdd:
		return l.Add(r), false
	case opSub:
		return l.Subtract(r), false
	case opLt:
		return l.LessThan(r), false
	}
	return Value{tag: tInvalid, inv: "unknown infix op"}, false
}

func evalIf(n *Node, ctx *Context) (Value, bool) {
	c, ret := eval(n.left, ctx)
	if ret {
		return c, true
	}
	if c.tag == tInvalid {
		return c, false
	}
	if c.IsTruthy() {
		return eval(n.body, ctx)
	}
	if n.right != nil {
		return eval(n.right, ctx)
	}
	return vNull(), false
}

func evalReturn(n *Node, ctx *Context) (Value, bool) {
	v := vNull()
	if n.right != nil {
		var ret bool
		v, ret = eval(n.right, ctx)
		if ret {
			return v, true
		}
	}
	return v, true
}

func evalBlock(n *Node, ctx *Context) (Value, bool) {
	blockCtx := ctx
	if n.hasLocals {
		blockCtx = &Context{parent: ctx}
	}
	last := vNull()
	for _, s := range n.list {
		v, returned := eval(s, blockCtx)
		if returned {
			return v, true
		}
		if v.tag == tInvalid {
			return v, false
		}
		last = v
	}
	return last, false
}

func evalFuncDecl(n *Node, ctx *Context) (Value, bool) {
	defCtx := ctx
	pNames := n.params
	bodyN := n.body
	npar := len(pNames)
	fn := &FunctionCommand{definitionCtx: defCtx, executeFunc: func(callerCtx *Context, args *ArrayValue) Value {
		var local *Context
		if npar == 0 {
			local = &Context{parent: defCtx}
		} else {
			vars := make(map[string]Value, npar)
			nv := len(args.values)
			for i, p := range pNames {
				if i < nv {
					vars[p] = args.values[i]
				}
			}
			local = &Context{parent: defCtx, variables: vars}
		}
		result, _ := eval(bodyN, local)
		return result
	}}
	ctx.Create(n.name, vFunc(fn))
	return vFunc(fn), false
}

func evalCall(n *Node, ctx *Context) (Value, bool) {
	callee, ret := eval(n.left, ctx)
	if ret {
		return callee, true
	}
	if callee.tag != tFunc {
		return Value{tag: tInvalid, inv: "call target not a function"}, false
	}
	nargs := len(n.list)
	av := &ArrayValue{values: make([]Value, nargs)}
	for i, a := range n.list {
		v, r2 := eval(a, ctx)
		if r2 {
			return v, true
		}
		av.values[i] = v
	}
	fc := callee.cmd.(*FunctionCommand)
	return fc.Execute(ctx, av), false
}

// fibAST builds:  def fib(n) { if (n < 2) { return n; } return fib(n-1) + fib(n-2); }
func fibAST() *Node {
	ident := func(name string) *Node { return &Node{kind: nkIdent, name: name} }
	intl := func(i int64) *Node { return &Node{kind: nkIntLit, iVal: i} }
	infix := func(op uint8, l, r *Node) *Node { return &Node{kind: nkInfix, op: op, left: l, right: r} }
	call := func(callee *Node, args ...*Node) *Node { return &Node{kind: nkCall, left: callee, list: args} }

	cond := infix(opLt, ident("n"), intl(2))
	thenBlk := &Node{kind: nkBlock, list: []*Node{{kind: nkReturn, right: ident("n")}}}
	ifStmt := &Node{kind: nkIf, left: cond, body: thenBlk}
	recur := infix(opAdd,
		call(ident("fib"), infix(opSub, ident("n"), intl(1))),
		call(ident("fib"), infix(opSub, ident("n"), intl(2))),
	)
	retStmt := &Node{kind: nkReturn, right: recur}
	body := &Node{kind: nkBlock, list: []*Node{ifStmt, retStmt}} // no `let` => hasLocals stays false
	return &Node{kind: nkFuncDecl, name: "fib", params: []string{"n"}, body: body}
}

func runTreeWalk(n int64) int64 {
	root := &Context{}
	decl := fibAST()
	eval(decl, root) // registers fib in root
	fib := root.Get("fib")
	av := &ArrayValue{values: []Value{vInt(n)}}
	res := fib.cmd.(*FunctionCommand).Execute(root, av)
	return res.i
}

// ----------------------------------------------------------------------------
// PART B: the bytecode VM (Lever 3) -- same Value, slot locals, flat dispatch
// ----------------------------------------------------------------------------

const (
	opConst uint8 = iota // operand a = const index
	opLoad               // operand a = local slot
	opAddOp
	opSubOp
	opLtOp
	opJumpIfFalse // operand a = absolute target
	opJump        // operand a = absolute target
	opCall        // operand a = function index, b = argc
	opReturn
)

type instr struct {
	op   uint8
	a    int32
	b    int32
}

type Chunk struct {
	code     []instr
	consts   []Value
	numSlots int // param + local count
	name     string
}

// compiler: AST function -> Chunk. fib subset (no `let` locals beyond params).
type compiler struct {
	funcIndex map[string]int // name -> chunk index, resolved at compile time
}

func (cp *compiler) compileFunc(fn *Node) *Chunk {
	ch := &Chunk{name: fn.name, numSlots: len(fn.params)}
	slots := map[string]int{}
	for i, p := range fn.params {
		slots[p] = i
	}
	cp.compileNode(fn.body, ch, slots)
	// safety terminator: return null if control falls off the end
	ch.consts = append(ch.consts, vNull())
	ch.code = append(ch.code, instr{op: opConst, a: int32(len(ch.consts) - 1)})
	ch.code = append(ch.code, instr{op: opReturn})
	return ch
}

func (cp *compiler) emit(ch *Chunk, in instr) int {
	ch.code = append(ch.code, in)
	return len(ch.code) - 1
}

func (cp *compiler) compileNode(n *Node, ch *Chunk, slots map[string]int) {
	switch n.kind {
	case nkBlock:
		for _, s := range n.list {
			cp.compileNode(s, ch, slots)
		}
	case nkReturn:
		if n.right != nil {
			cp.compileNode(n.right, ch, slots)
		} else {
			ch.consts = append(ch.consts, vNull())
			cp.emit(ch, instr{op: opConst, a: int32(len(ch.consts) - 1)})
		}
		cp.emit(ch, instr{op: opReturn})
	case nkIf:
		cp.compileNode(n.left, ch, slots) // condition -> stack top
		jf := cp.emit(ch, instr{op: opJumpIfFalse}) // patched
		cp.compileNode(n.body, ch, slots)
		// fib's then-branch always returns, so no else/merge jump needed; but
		// emit a jump-over for generality when an else exists.
		if n.right != nil {
			jOver := cp.emit(ch, instr{op: opJump})
			ch.code[jf].a = int32(len(ch.code))
			cp.compileNode(n.right, ch, slots)
			ch.code[jOver].a = int32(len(ch.code))
		} else {
			ch.code[jf].a = int32(len(ch.code))
		}
	case nkIntLit:
		ch.consts = append(ch.consts, vInt(n.iVal))
		cp.emit(ch, instr{op: opConst, a: int32(len(ch.consts) - 1)})
	case nkIdent:
		if slot, ok := slots[n.name]; ok {
			cp.emit(ch, instr{op: opLoad, a: int32(slot)})
		} else {
			panic("vm prototype: unresolved ident " + n.name)
		}
	case nkInfix:
		cp.compileNode(n.left, ch, slots)
		cp.compileNode(n.right, ch, slots)
		switch n.op {
		case opAdd:
			cp.emit(ch, instr{op: opAddOp})
		case opSub:
			cp.emit(ch, instr{op: opSubOp})
		case opLt:
			cp.emit(ch, instr{op: opLtOp})
		}
	case nkCall:
		for _, a := range n.list {
			cp.compileNode(a, ch, slots)
		}
		fidx, ok := cp.funcIndex[n.left.name]
		if !ok {
			panic("vm prototype: unknown function " + n.left.name)
		}
		cp.emit(ch, instr{op: opCall, a: int32(fidx), b: int32(len(n.list))})
	default:
		panic("vm prototype: unhandled node kind in compiler")
	}
}

type frame struct {
	chunk *Chunk
	pc    int
	base  int // stack index where this frame's slots begin
}

type VM struct {
	chunks []*Chunk
	stack  []Value
	sp     int
	frames []frame
	fp     int
}

func newVM(chunks []*Chunk) *VM {
	return &VM{
		chunks: chunks,
		stack:  make([]Value, 1<<16), // reused; no per-call heap alloc
		frames: make([]frame, 1<<12),
	}
}

func (vm *VM) push(v Value) { vm.stack[vm.sp] = v; vm.sp++ }

// run executes chunk `entry` with `args` already describing the single top-level call.
func (vm *VM) run(entry int, arg int64) int64 {
	vm.sp = 0
	vm.fp = 0
	ch := vm.chunks[entry]
	vm.push(vInt(arg)) // the one argument occupies slot 0
	vm.frames[0] = frame{chunk: ch, pc: 0, base: 0}
	vm.fp = 1

	for {
		fr := &vm.frames[vm.fp-1]
		code := fr.chunk.code
		in := code[fr.pc]
		fr.pc++
		switch in.op {
		case opConst:
			vm.push(fr.chunk.consts[in.a])
		case opLoad:
			vm.push(vm.stack[fr.base+int(in.a)])
		case opAddOp:
			b := vm.stack[vm.sp-1]
			a := vm.stack[vm.sp-2]
			vm.sp--
			vm.stack[vm.sp-1] = Value{tag: tInt, i: a.i + b.i}
		case opSubOp:
			b := vm.stack[vm.sp-1]
			a := vm.stack[vm.sp-2]
			vm.sp--
			vm.stack[vm.sp-1] = Value{tag: tInt, i: a.i - b.i}
		case opLtOp:
			b := vm.stack[vm.sp-1]
			a := vm.stack[vm.sp-2]
			vm.sp--
			vm.stack[vm.sp-1] = Value{tag: tBool, b: a.i < b.i}
		case opJumpIfFalse:
			c := vm.stack[vm.sp-1]
			vm.sp--
			if !c.IsTruthy() {
				fr.pc = int(in.a)
			}
		case opJump:
			fr.pc = int(in.a)
		case opCall:
			callee := vm.chunks[in.a]
			argc := int(in.b)
			newBase := vm.sp - argc
			// reserve any extra local slots beyond the args (fib: none)
			for i := argc; i < callee.numSlots; i++ {
				vm.stack[newBase+i] = vNull()
			}
			vm.sp = newBase + callee.numSlots
			vm.frames[vm.fp] = frame{chunk: callee, pc: 0, base: newBase}
			vm.fp++
		case opReturn:
			result := vm.stack[vm.sp-1]
			retBase := fr.base
			vm.fp--
			vm.sp = retBase
			if vm.fp == 0 {
				return result.i
			}
			vm.push(result)
		}
	}
}

func compileProgram() (*VM, int) {
	fib := fibAST()
	cp := &compiler{funcIndex: map[string]int{"fib": 0}}
	ch := cp.compileFunc(fib)
	return newVM([]*Chunk{ch}), 0
}

func runVM(n int64) int64 {
	vm, entry := compileProgram()
	return vm.run(entry, n)
}

// ----------------------------------------------------------------------------
// PART C: vmLean -- identical VM but an int64 stack (Lever 3 + Lever 2 ceiling)
// ----------------------------------------------------------------------------

type vmLean struct {
	chunks []*Chunk
	stack  []int64
	sp     int
	frames []frame
	fp     int
}

func newVMLean(chunks []*Chunk) *vmLean {
	return &vmLean{chunks: chunks, stack: make([]int64, 1<<16), frames: make([]frame, 1<<12)}
}

func (vm *vmLean) run(entry int, arg int64) int64 {
	vm.sp, vm.fp = 0, 0
	ch := vm.chunks[entry]
	vm.stack[vm.sp] = arg
	vm.sp++
	vm.frames[0] = frame{chunk: ch, pc: 0, base: 0}
	vm.fp = 1
	for {
		fr := &vm.frames[vm.fp-1]
		in := fr.chunk.code[fr.pc]
		fr.pc++
		switch in.op {
		case opConst:
			vm.stack[vm.sp] = fr.chunk.consts[in.a].i
			vm.sp++
		case opLoad:
			vm.stack[vm.sp] = vm.stack[fr.base+int(in.a)]
			vm.sp++
		case opAddOp:
			vm.sp--
			vm.stack[vm.sp-1] = vm.stack[vm.sp-1] + vm.stack[vm.sp]
		case opSubOp:
			vm.sp--
			vm.stack[vm.sp-1] = vm.stack[vm.sp-1] - vm.stack[vm.sp]
		case opLtOp:
			vm.sp--
			if vm.stack[vm.sp-1] < vm.stack[vm.sp] {
				vm.stack[vm.sp-1] = 1
			} else {
				vm.stack[vm.sp-1] = 0
			}
		case opJumpIfFalse:
			vm.sp--
			if vm.stack[vm.sp] == 0 {
				fr.pc = int(in.a)
			}
		case opJump:
			fr.pc = int(in.a)
		case opCall:
			callee := vm.chunks[in.a]
			argc := int(in.b)
			newBase := vm.sp - argc
			vm.sp = newBase + callee.numSlots
			vm.frames[vm.fp] = frame{chunk: callee, pc: 0, base: newBase}
			vm.fp++
		case opReturn:
			result := vm.stack[vm.sp-1]
			retBase := fr.base
			vm.fp--
			vm.sp = retBase
			if vm.fp == 0 {
				return result
			}
			vm.stack[vm.sp] = result
			vm.sp++
		}
	}
}

func runVMLean(n int64) int64 {
	fib := fibAST()
	cp := &compiler{funcIndex: map[string]int{"fib": 0}}
	ch := cp.compileFunc(fib)
	vm := newVMLean([]*Chunk{ch})
	return vm.run(0, n)
}

// ----------------------------------------------------------------------------
// Harness
// ----------------------------------------------------------------------------

func expectedFib(n int64) int64 {
	if n < 2 {
		return n
	}
	a, b := int64(0), int64(1)
	for i := int64(2); i <= n; i++ {
		a, b = b, a+b
	}
	return b
}

type result struct {
	name    string
	minWall time.Duration
	allocs  uint64 // mallocs for ONE fib(n)
	bytes   uint64 // bytes allocated for ONE fib(n)
	out     int64
}

func bench(name string, n int64, repeats int, f func(int64) int64) result {
	f(n) // warmup (also forces compile)
	best := time.Duration(1<<62)
	var out int64
	for r := 0; r < repeats; r++ {
		start := time.Now()
		out = f(n)
		if d := time.Since(start); d < best {
			best = d
		}
	}
	// allocation accounting for a single call
	var m0, m1 runtime.MemStats
	runtime.GC()
	runtime.ReadMemStats(&m0)
	f(n)
	runtime.ReadMemStats(&m1)
	return result{name: name, minWall: best, allocs: m1.Mallocs - m0.Mallocs, bytes: m1.TotalAlloc - m0.TotalAlloc, out: out}
}

func main() {
	runtime.GOMAXPROCS(1)
	n := int64(32)
	repeats := 5
	if len(os.Args) > 1 {
		if v, err := strconv.ParseInt(os.Args[1], 10, 64); err == nil {
			n = v
		}
	}
	if len(os.Args) > 2 {
		if v, err := strconv.Atoi(os.Args[2]); err == nil {
			repeats = v
		}
	}

	want := expectedFib(n)
	results := []result{
		bench("treeWalk", n, repeats, runTreeWalk),
		bench("vm (Lever3, 88B Value)", n, repeats, runVM),
		bench("vmLean (Lever3+leanValue)", n, repeats, runVMLean),
	}

	for _, r := range results {
		if r.out != want {
			fmt.Printf("CORRECTNESS FAILURE: %s fib(%d)=%d want %d\n", r.name, n, r.out, want)
			os.Exit(1)
		}
	}

	fmt.Printf("fib(%d) = %d  | repeats=%d  GOMAXPROCS=1  go=%s\n\n", n, want, repeats, runtime.Version())
	fmt.Printf("%-30s %14s %14s %16s\n", "engine", "min wall", "allocs/call", "bytes/call")
	base := results[0].minWall
	for _, r := range results {
		fmt.Printf("%-30s %14s %14d %16d\n", r.name, r.minWall.Round(time.Microsecond), r.allocs, r.bytes)
	}
	fmt.Printf("\nspeedup vs treeWalk (min wall):\n")
	for _, r := range results[1:] {
		fmt.Printf("  %-28s %6.2fx\n", r.name, float64(base)/float64(r.minWall))
	}
}
