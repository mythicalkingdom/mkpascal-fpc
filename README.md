# MKPascal-FPC

A Turbo Pascal style interpreter written in Free Pascal, designed to be embedded: a host program gives each
session a **terminal** (`TMKTerm`) and a **file harness** (`TMKFiles`), and the interpreter never touches the
screen, keyboard or file system any other way. It is the Free Pascal port of the JavaScript `mkpascal`
(`../mkpascal`) and shares its goals: familiar to use, no graphics, no hardware access, many sessions at once.

## Build and run

```
make            # needs fpc 3.2.x; builds bin/mkpas, bin/runtests, bin/test_api, bin/embed
make test       # 99 program tests (tests/cases) + embedding API checks
bin/mkpas examples/hello.pas
```

## Embedding

```pascal
uses mkp_harness, mkpascal;

Term    := TConsoleTerm.Create;                       // or your own TMKTerm
Files   := TDiskFiles.Create('/data/users/42');       // or TMemoryFiles, TDenyFiles, your own TMKFiles
Session := TMKSession.Create(Term, Files);
Session.MaxSteps := 5000000;                          // limits for programs you do not trust
Session.MaxRuntimeMs := 20000;
Session.MaxOutputChars := 1000000;
Session.MemoryBytes := 4 * 1024 * 1024;               // the Pascal memory: globals + heap + stack
if Session.LoadSource(Text) then
  Status := Session.Run                               // rsEnd, rsHalt, rsError, rsLimit, rsBreak
else
  Term.Write(Session.LastError);
// from another thread:  Session.RequestBreak;
```

* **`TMKTerm`** (`mkp_harness.pas`): `Write`, `ReadLine` (blocking) are required; `ReadKey`, `KeyPressed`,
  `ClearScreen`, `GotoXY`, `GetXY`, `SetColor`, `PrinterWrite`, `LineEndEchoed`, `EndSession` have defaults.
  Provided: `TConsoleTerm` (stdin/stdout) and `TBufferTerm` (scripted, for tests).
* **`TMKFiles`**: `ReadFile`, `WriteFile`, `Exists`, `Remove`, `Rename`, `List`, and optional `HasDates`/`Stat`/`SetTime`.
  Errors are `EMKFile` with a Node-style `Code` (ENOENT, EEXIST, EACCES, EINVAL, ENOTDIR, EPERM). Provided:
  `TDiskFiles` (confined to one directory), `TMemoryFiles` (with a clock for deterministic dates), `TDenyFiles`.
* **`TMKSession`**: one per user. `LoadSource`/`LoadFile`, `Run`, `RequestBreak`, `AddInclude`, `AddUnit`, `Define`,
  `Params`, `Clock`, `ExitCode`, `LastError`, `OnYield`. Include files are read through the harness, so they live where the user's
  other files live. A session can be run again after it finishes.
* See `examples/embed.pas` for a custom terminal and a logging file harness.

## The language

Turbo Pascal 5.5/7 core with the Turbo Pascal byte layout: 16-bit `Integer`, strings as a length byte plus
characters (`s[0]`, writing past the length, `FillChar(s, ...)`), 6-byte `Real`, sets as bitmaps, records with
variant parts overlaid, typed and untyped files, `BlockRead`/`BlockWrite`, `Move`/`FillChar`, `{$I-}`/`IOResult`,
untyped `var` parameters, variable typecasts (also as assignment targets), `{$I file}` includes, conditional
compilation, `uses Crt, Dos, Printer`.

Also: **objects** (single inheritance, static and virtual methods through a real VMT slot in the object's bytes,
constructors/destructors, `inherited`, `TParent.Init`, `Fail`, `TypeOf`, `New(p, Init(...))`, `Dispose(p, Done)`),
**units** (`unit ... interface ... implementation ... initialization`, found as `NAME.PAS` through the file harness
or registered with `Session.AddUnit`; qualified names, shadowing, init order, implementation-side cycles) and the
**Dos routines** through the harness (`FindFirst/FindNext`, `GetFTime/SetFTime`, `GetDate/GetTime` from a clock you
can set, `PackTime/UnpackTime`, `FSplit`, `FExpand`, `SearchRec`, `DateTime`, `DosError`).

**Procedural types** (`type TFn = function(x: integer): integer;`, `@Foo`, arrays and fields of them, callbacks),
local **`goto`** and **open array parameters** (`array of T`, value/`var`/`const`, `High`) are in too. Everything the
JavaScript version runs now runs here, including its `invent` example (units, objects, `Fail`, a sort callback, Crt,
typed files). See `CLAUDE.md` for the design notes.
