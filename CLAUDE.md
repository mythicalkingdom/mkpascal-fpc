# CLAUDE.md

## Project overview

MKPascal-FPC is a Free Pascal port of `../mkpascal` (a Turbo Pascal 5.5/7 style interpreter in JavaScript).
It is built to be embedded: `TMKSession.Create(Term, Files)` takes a terminal (`TMKTerm`) and a file harness
(`TMKFiles`); nothing else reaches the outside world. Same goals as the JS project: familiar to use, not exact;
no graphics, no hardware access, no binary-level compatibility, many sessions at once (one thread each).
Build with `make` (fpc 3.2.2, `{$mode objfpc}{$H+}`), test with `make test`.

## Files (src/)

| Unit | Role |
|---|---|
| `mkp_defs.pas` | exceptions: `EMKCompile` (line, col, file, unit), `EMKRuntime` (TP error code), `EMKHalt`, `EMKLimit`, `EMKBreak`; `RuntimeMessage` |
| `mkp_harness.pas` | the embedding interfaces `TMKTerm`, `TMKFiles` and the implementations `TConsoleTerm`, `TBufferTerm`, `TDiskFiles`, `TMemoryFiles`, `TDenyFiles` |
| `mkp_lexer.pas` | tokens; comments; directives: `{$I file}` includes, `{$DEFINE/UNDEF/IFDEF/IFNDEF/IFOPT/ELSE/ENDIF}`, switches (a bit mask per token) |
| `mkp_types.pas` | `TType` descriptors with TP sizes/layout, `TTypeStore` (owns all types), assignment compatibility |
| `mkp_mem.pas` | `TMem`: the byte-addressed arena (globals, heap with free list, stack), typed access, 6-byte Real |
| `mkp_run.pas` | `TRun`: stack/frame pointers, limits, console input, Pascal files on the harness, Random, number formatting |
| `mkp_nodes.pas` | the executable tree: expression and statement node classes |
| `mkp_builtins.pas` | predeclared procedures/functions (System, Crt, files) as nodes, `Write`/`Read` statements |
| `mkp_compiler.pas` (+ `mkp_comp_a/b/c/d.inc`) | one-pass parser that type checks and builds nodes directly: A = infrastructure, types, declarations, routines; B = expressions; C = predeclared routines, statements, program; D = units and objects |
| `mkpascal.pas` | the public API `TMKSession` |
| `mkpas.pas` | command line runner (console terminal + disk harness) |

## Key design points

- **Real memory.** Every variable lives in one `TMem` arena in its Turbo Pascal layout (integers 1/2/4 bytes,
  strings length byte + characters, sets bitmaps, records packed, variants overlaid). Addresses are 32-bit offsets
  (`TAddr`), 0 is nil. This makes `s[0]`, string tails, `Move`/`FillChar`/`BlockRead`/`BlockWrite` on any variable,
  variable typecasts (`WordRec(n).Hi`, also assignable) and untyped `var` parameters (just an address) plain
  memory operations — the things the JS version emulated with hidden tails and byte images.
- **Memory map.** `[16 .. GlobalEnd)` globals (typed constants and scratch temporaries too), then the heap
  (`InitHeap`, first fit, 8-byte headers), then the stack at the top growing down. `StackBase` is the lowest stack
  address. Out of heap = runtime error 203, out of stack or `MaxCallDepth` = 202, bad address = 204.
- **Frames.** A call reserves `FrameSize` bytes below `SP`, evaluates arguments into it (nested calls go below),
  stores the static link at offset 0, then runs the body. Parameters start at offset 8, then the function result,
  then locals and temporaries. Variables are `TGlobalAddr`, `TLocalAddr(offset, hops)` (hops = static link walks) or
  `TVarParamAddr` (the slot holds the address). The main program is level 0; `Level` of a routine is its nesting.
- **Typed nodes.** `TExpr.ExprClass` decides how a node is evaluated: ordinals/pointers `EvalI` (Int64), reals
  `EvalR`, strings `EvalS` (ShortString), sets `EvalSet` (32-byte bitmap), records/arrays `EvalA` (address).
  Lvalues are `TAddrExpr` nodes; `RValue` wraps them in a load. Assignments store through `StoreValue`.
- **Ownership.** Every node registers itself in `NodePool` (a threadvar set while compiling) and is freed with the
  `TProgramImage`; types are owned by `TTypeStore`.
- **FPC pitfall.** Inside a function, its own bare name is the result variable, so recursive calls must be written
  `ParseStatement()` / `ParseType()` / `ParseFactor()` with parentheses.
- **I/O errors.** `IOEnter(C, Soft)` is the Turbo Pascal rule: a pending `IOResult` makes the next I/O fail (default)
  or be skipped (`{$I-}`, a per-token switch). File errors map to TP codes 2 3 4 5 100-106.
- **Limits and break.** Loop back-edges and calls `Tick`; every 2048 ticks `CheckLimits` checks the break flag
  (`RequestBreak` is thread-safe), step/time/output limits and calls `OnYield`.
- **Line numbers.** `TStmt.Run` records `C.LineNo`; runtime errors print `Runtime error N: text at line L.`

## Objects

- `type T = object(Parent) fields; methods end;` An instance is plain bytes: the flattened fields (parent first) and, in
  the type that first has a virtual method, a 2-byte **VMT id** (`VmtOff`; `TType.VmtId` is 1-based into
  `TProgramImage.ObjTypes` = `TRun.ObjTypes`). `TType.Vtab` holds the virtual methods by slot (`TRoutine.VIndex`); a
  descendant copies the parent's table and replaces the slots it overrides (a method with a virtual ancestor of the
  same name overrides it even without `virtual`).
- A method is a `TRoutine` whose parameter 0 is `Self` (a var-style parameter at frame offset 8; the object's address).
  `TCallExpr.SelfExpr` evaluates the address first, optionally stores the constructor's VMT id (`SetVmtId`: a
  constructor called through a designator sets it, `inherited`/`TParent.Init` calls do not), and picks the routine
  from the VMT when `VirtIndex >= 0`. A virtual call through an object whose VMT id is 0 (constructor never ran) is
  runtime error 204.
- Inside a method the fields (`skField` with `SelfSym`) and methods (`skMethod`) of the object are symbols in a scope
  above the parameters; `with obj do` does the same through a hidden pointer slot. `BuildMethodCall` builds every
  method call (`obj.M`, bare `M` in a method, `with`, `inherited`, `TParent.M`).
- Constructors are Boolean-valued (`TCallExpr.IsCtor`, `CtorOk`); `Fail` (`biFail`, sgExit + `C.Failed`) makes the
  call False; `New(p, Init(..))` frees the block and sets `p := nil` on failure (also the function form
  `p := New(PType, Init(..))`); `Dispose(p, Done)` runs the destructor first; `TypeOf` is the VMT id (`biTypeOf`).
- Method bodies are implemented as `procedure TFoo.Bar;` and found through `TType.Methods`; unimplemented methods are
  reported at the end of the program or unit (`FMethods`, `CheckMethodsDefined`).

## Units

- `unit N; interface ... implementation ... [initialization|begin] end.` `UseUnit` compiles a unit **in the same
  compiler instance** by swapping the lexer: its declarations use the shared image, the single global frame and the
  node pool. `TUnitInfo.Scope` holds the interface declarations (`ExportScope` is what clients import); the
  implementation sees `Scope` plus an import scope (`Scope.Parent` is re-pointed to it, so the unit's own names win).
  Imports go through non-owning scopes (`NewImportScope`, `ImportSyms`; a later unit shadows an earlier one).
- Interface routines are forward declarations (`Intf`); the implementation completes them (its header may omit the
  parameters). `Unit.Name` is resolved by `ResolveAhead`/`ResolveCurrent` (used for expressions, statements and
  types) unless a variable with the unit's name is in scope. Builtin units (Crt, Dos, Printer, System, Strings) are
  registered with `ExportScope = nil`.
- Source: `TMKSession.AddUnit` first, then `NAME.PAS` through the file harness. A cycle through interface `uses` is
  `Circular unit reference`; a cycle through implementation `uses` is fine (the unit's interface is complete before its
  implementation starts). Initialization parts run before the main program, dependencies first (`UnitInits`).
- Errors inside a unit carry `EMKCompile.InUnit`: `Error: ... (unit Bad, line 7, column 3)`.

## Dos

`SearchRec` (43 bytes, name `string[12]`; the Fill area holds the search handle and position), `DateTime`, `DosError`,
`AnyFile`... are predeclared; the routines are `TBuiltinStmt`/`TBuiltinExpr` ids using the file harness: `FindFirst`
lists the harness and matches wildcards (`TRun.FindFirstFile`), `Stat` supplies size and time (a harness without
dates gives size only), `GetFTime`/`SetFTime` use the open file (`pendingTime` is re-applied after each flush),
`GetDate`/`GetTime` read `TRun.Clock`. Times are DOS packed local time.

## Procedural types, goto, open arrays

- **Procedural types.** `type TFn = function(x: integer): integer;` is a `tyProc` type (`Params` with frame offsets, `Ret`),
  4 bytes holding a routine's number in `TProgramImage.ProcTable` (= `TRun.ProcTable`; 0 is nil). `@Foo`, or a bare
  routine name where a procedural value is expected (`ParseExprFor`: assignments, arguments, typed constants), gives
  `ProcRef`: a `TConstInt` of the number. Only level-1 routines can be taken (nested, methods and standard routines are
  compile errors). A call through a value is a `TCallExpr` with `ProcExpr` (`BuildProcCall`, from `f(x)`, `f;`, `rec.cb`,
  `ops[i](2)`); `Invoke` picks the routine from the table, so frame size, static link and result offset come from the
  routine actually called. Compatibility is structural (`ProcCompat`). Calling nil is runtime error 204.
- **goto.** `TGoto` returns `sgGoto` with `TRun.GotoLabel`; loops, `if`, `case` and `with` pass it up and a `TCompound` that
  declares the label (`LabelIds/LabelIdx`, filled by `ParseLabels` for `label:` at the start of statements in a list)
  restarts at it (ticking the step counter). Labels are checked at compile time (`TLabelState` per routine/unit/program,
  `TLabelFrame` per statement list, `ResolveGotos`): a label must be in the statement list of the goto or an enclosing one
  of the same routine, so jumping into a statement or out of a routine is a compile error.
- **Open arrays.** `array of T` parameters (value, `var`, `const`) are `tyOpenArray`: the parameter slot holds the address
  and the highest index (8 bytes). `a[i]` is `TOpenIndexAddr` (range checked, error 201), `High(a)` is `TOpenHigh`, `Low(a)`
  is 0, and `LValueOf` turns an open array into `TOpenData` (its data address) for `Move`/`FillChar`/`BlockRead`. The call
  builds the slot in `TCallExpr.Invoke` (`TArg.IsOpen`): an actual array passes its address and bounds, an open array
  parameter passes its slot on (`FromOpen`), and a *value* parameter gets a private heap copy freed when the call ends.

## Strings and Objects units

- `PChar` is `TTypeStore.TPChar` (`^Char`). `Compiler.PCharArg` turns a string constant (null terminated copy in global
  memory via `AddInit`) or a zero based char array lvalue (`TAddrOf`) into a PChar; `Coerce` also converts such arrays and
  PChar to `string` (`TPCharToStr`). `p[i]` is `TPtrIndexAddr`, `p+n`/`p-q` are `TIntBin` with `wNone`/`wI32`.
  The `biStr*` routines live in `StrFunc` (mkp_builtins) over `CLen`/`CByte`; used as statements they become `TEvalStmt`.
- `Dispose` takes an rvalue pointer (`Dispose(PObject(@Self), Done)`), no longer an lvalue.
- `Objects` is real Pascal in `units/OBJECTS.PAS`; `tools/embed_units.py` (`make units`) generates `src/mkp_stdunits.pas`
  (committed). `UseUnit` asks the host's unit source first, then `StdUnitSource`.
- Method prototypes inside an object declaration are laid out before the object's size is known, so
  `ParseObjectDecl` recomputes every method's parameter offsets and frame size once `Obj.Size` is set (a by-value
  parameter of the object's own type used to overlap the frame).

## Host calls

`HostCall(Cmd: string): string` is a predeclared function (`biHostCall`): a question to the program the interpreter is embedded in, answered by `TMKTerm.HostCall(Cmd, Err)` (a virtual method like `ReadKey`; the default has no host and the call is run-time error 300 "Host call failed: ..."). A non-empty `Err` is the same error with that text. Added for mk's scripts (`../mk-fpc/MHOST-PLAN.md`); tested from mk (`tests/hosttest.py`).

## Tests

- `tests/cases/NAME.pas` + `NAME.out` (+ `.in` lines for ReadLn, `.keys` for ReadKey), run by `bin/runtests`;
  `NAME.out` starting with `!compile TEXT` expects a compile error containing TEXT. Most outputs were produced by the
  JavaScript interpreter (differential testing); `blockio`, `variant_records`, `string_funcs`, `heap`, `crt_keys`,
  `typecasts` are hand-checked because the byte-addressed memory is *closer to real Turbo Pascal* than the JS
  version (a BlockRead that starts mid-array runs on past the array; variants really overlay; `Pos('', s)` is 0).
- `tests/test_api.pas`: the embedding API (limits, break from another thread, harnesses, includes, defines, params).
- Add a case with every change. Beware: identifiers are case-insensitive, so a type `P` and a variable `p` clash.

## Status

Done: procedural types, goto, open arrays, objects, units and the Dos routines (see above); lexer with includes and conditional compilation; types (integers, Real family, Boolean, Char, enums,
subranges, strings, arrays, records with variants, sets, pointers, files); constants and typed constants;
procedures/functions (nested, forward, value/var/const/untyped parameters, recursion); all statements except
`goto`; System/Crt/file builtins; console and file I/O with `{$I-}`; heap; session API and limits.

Not yet: performance work (specialised nodes for common patterns), non-local `goto`. Verified against real code: the MKSTRING unit (35 routines, conditional
compilation, includes, string idioms) gives the same output as the JavaScript interpreter.
