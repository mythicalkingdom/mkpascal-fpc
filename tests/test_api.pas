{ SPDX-License-Identifier: GPL-3.0-or-later }
program test_api;
// Tests of the embedding API: limits, break, harnesses, error reporting.
{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX} cthreads, {$ENDIF}
  SysUtils, Classes, DateUtils, mkp_harness, mkpascal, HostReg;

var
  Failures, Total: Integer;

procedure Check(Cond: Boolean; const Msg: string);
begin
  Inc(Total);
  if not Cond then begin Inc(Failures); WriteLn('FAIL: ', Msg); end;
end;

function Norm(const S: string): string;
begin
  Result := StringReplace(S, #13#10, '|', [rfReplaceAll]);
end;

type
  THostDemo = class
    function Handle(const Verb: string; Args: TStrings; Res: THostResult; out Err: string): Boolean;
  end;

  TBreaker = class(TThread)
  public
    S: TMKSession;
    constructor Create(ASession: TMKSession);
  protected
    procedure Execute; override;
  end;

function THostDemo.Handle(const Verb: string; Args: TStrings; Res: THostResult; out Err: string): Boolean;
begin
  Result := True;
  if Verb = 'demo.list' then
  begin
    Res.Table(['name', 'n']);
    Res.Row(['alpha', '1']);
    Res.Row(['beta', '2']);
  end
  else begin Err := 'no such demo command'; Result := False; end;
end;

constructor TBreaker.Create(ASession: TMKSession);
begin
  S := ASession;
  inherited Create(False);
end;

procedure TBreaker.Execute;
begin
  Sleep(50);
  S.RequestBreak;
end;

function FixedClock: TDateTime;
begin
  Result := EncodeDate(2001, 2, 3);
end;

function Fresh(out Term: TBufferTerm; out Files: TMemoryFiles): TMKSession;
begin
  Term := TBufferTerm.Create;
  Files := TMemoryFiles.Create;
  Result := TMKSession.Create(Term, Files);
end;

var
  S: TMKSession;
  T: TBufferTerm;
  F: TMemoryFiles;
  St: TMKRunStatus;
  Demo: THostDemo;
  B: TBreaker;
  Dir: string;
  D: TDiskFiles;
  Names: TStringList;
  SZ: Int64;
  MT: TDateTime;
  Raised: Boolean;
  Txt: string;
begin
  { compile error text }
  S := Fresh(T, F);
  Check(not S.LoadSource('program t;'#10'begin'#10'  x := 1;'#10'end.'), 'unknown identifier is a compile error');
  Check(Pos('Unknown identifier ''x'' (line 3, column 3)', S.LastError) > 0, 'error position: ' + S.LastError);
  S.Free; F.Free; T.Free;

  { runtime error text and exit code }
  S := Fresh(T, F);
  Check(S.LoadSource('program t; var i: integer; begin i := 0; writeln(1 div i) end.'), 'compiles');
  St := S.Run;
  Check(St = rsError, 'division by zero is rsError');
  Check(S.ExitCode = 200, 'exit code is the runtime error number');
  Check(Norm(T.Output) = '|Runtime error 200: Division by zero at line 1.|', 'runtime error text: ' + Norm(T.Output));
  S.Free; F.Free; T.Free;

  { Halt }
  S := Fresh(T, F);
  S.LoadSource('program t; begin writeln(''a''); halt(7); writeln(''b'') end.');
  St := S.Run;
  Check((St = rsHalt) and (S.ExitCode = 7) and (Norm(T.Output) = 'a|'), 'halt(7)');
  S.Free; F.Free; T.Free;

  { step limit stops a runaway loop }
  S := Fresh(T, F);
  S.MaxSteps := 100000;
  S.LoadSource('program t; begin while true do ; end.');
  Check(S.Run = rsLimit, 'step limit');
  Check(Pos('Step limit exceeded', T.Output) > 0, 'step limit message');
  S.Free; F.Free; T.Free;

  { output limit }
  S := Fresh(T, F);
  S.MaxOutputChars := 50;
  S.LoadSource('program t; var i: integer; begin for i := 1 to 1000 do writeln(''line '', i) end.');
  Check(S.Run = rsLimit, 'output limit');
  S.Free; F.Free; T.Free;

  { run time limit }
  S := Fresh(T, F);
  S.MaxRuntimeMs := 100;
  S.LoadSource('program t; begin while true do ; end.');
  Check(S.Run = rsLimit, 'time limit');
  S.Free; F.Free; T.Free;

  { stack depth and memory }
  S := Fresh(T, F);
  S.LoadSource('program t; procedure f(n: integer); begin f(n + 1) end; begin f(1) end.');
  Check(S.Run = rsError, 'endless recursion is a runtime error');
  Check(S.ExitCode = 202, 'stack overflow is error 202: ' + IntToStr(S.ExitCode));
  S.Free; F.Free; T.Free;

  S := Fresh(T, F);
  S.MemoryBytes := 256 * 1024;
  S.StackBytes := 64 * 1024;
  S.LoadSource('program t; type PBig = ^Big; Big = array[1..1000] of integer; var p: PBig; i: integer; begin for i := 1 to 1000 do new(p) end.');
  Check(S.Run = rsError, 'heap exhaustion is a runtime error');
  Check(S.ExitCode = 203, 'heap overflow is error 203: ' + IntToStr(S.ExitCode));
  S.Free; F.Free; T.Free;

  { RequestBreak from another thread }
  S := Fresh(T, F);
  S.LoadSource('program t; begin while true do ; end.');
  B := TBreaker.Create(S);
  St := S.Run;
  B.WaitFor;
  B.Free;
  Check(St = rsBreak, 'RequestBreak interrupts the program');
  S.Free; F.Free; T.Free;

  { the file harness sees every file access; deny gives error 5 }
  T := TBufferTerm.Create;
  S := TMKSession.Create(T, TDenyFiles.Create);
  S.LoadSource('program t; var f: text; begin assign(f, ''x''); rewrite(f) end.');
  Check(S.Run = rsError, 'deny harness');
  Check(S.ExitCode = 5, 'file access denied is error 5');
  S.Files.Free;
  S.Free; T.Free;

  { memory harness: dates through GetFTime-like stat }
  F := TMemoryFiles.Create;
  F.WriteFile('a.txt', 'hello');
  F.Stat('A.TXT', SZ, MT);
  Check(SZ = 5, 'memory harness size');
  Check(F.HasDates, 'memory harness has dates');
  F.SetTime('a.txt', EncodeDate(1999, 1, 2));
  F.Stat('a.txt', SZ, MT);
  Check(Trunc(MT) = Trunc(EncodeDate(1999, 1, 2)), 'SetTime');
  F.Rename('a.txt', 'b.txt');
  F.Stat('b.txt', SZ, MT);
  Check(Trunc(MT) = Trunc(EncodeDate(1999, 1, 2)), 'rename keeps the time');
  Raised := False;
  try F.ReadFile('a.txt'); except on E: EMKFile do Raised := E.Code = 'ENOENT'; end;
  Check(Raised, 'ENOENT after rename');
  F.Free;

  { disk harness: confined to its directory, case-insensitive }
  Dir := GetTempDir + 'mkp_test_' + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(Dir);
  try
    D := TDiskFiles.Create(Dir);
    try
      D.WriteFile('Hello.TXT', 'abc');
      Check(D.ReadFile('hello.txt') = 'abc', 'disk harness is case-insensitive');
      Raised := False;
      try D.ReadFile('../etc/passwd'); except on E: EMKFile do Raised := E.Code = 'EACCES'; end;
      Check(Raised, 'disk harness refuses ..');
      Raised := False;
      try D.ReadFile('nope.txt'); except on E: EMKFile do Raised := E.Code = 'ENOENT'; end;
      Check(Raised, 'disk harness ENOENT');
      Names := TStringList.Create;
      D.List(Names);
      Check((Names.Count = 1) and SameText(Names[0], 'Hello.TXT'), 'disk harness list');
      Names.Free;
      D.Stat('hello.txt', SZ, MT);
      Check(SZ = 3, 'disk harness stat size');
      Check(Abs(Now - MT) < 1, 'disk harness stat time is recent');
      D.Remove('HELLO.txt');
      Check(not D.Exists('hello.txt'), 'disk harness remove');
    finally
      D.Free;
    end;
  finally
    RemoveDir(Dir);
  end;

  { include files: registered text and through the harness }
  S := Fresh(T, F);
  S.AddInclude('body.inc', 'writeln(''from include'');');
  F.WriteFile('consts.pas', 'const Answer = 42;');
  Check(S.LoadSource('program t; {$I consts} begin {$I body.inc} writeln(Answer) end.'), 'includes load: ' + S.LastError);
  S.Run;
  Check(Norm(T.Output) = 'from include|42|', 'includes run');
  S.Free; F.Free; T.Free;

  { conditional compilation symbols from the host }
  S := Fresh(T, F);
  S.Define('SPECIAL');
  S.LoadSource('program t; begin {$IFDEF SPECIAL} writeln(''special''); {$ELSE} writeln(''plain''); {$ENDIF} end.');
  S.Run;
  Check(Norm(T.Output) = 'special|', 'host define');
  S.Free; F.Free; T.Free;

  { units: read through the file harness as NAME.PAS, or registered with AddUnit }
  S := Fresh(T, F);
  F.WriteFile('Geom.pas', 'unit Geom; interface function Twice(n: integer): integer; implementation ' +
    'function Twice(n: integer): integer; begin Twice := n * 2 end; end.');
  Check(S.LoadSource('program t; uses geom; begin writeln(Twice(21)) end.'), 'unit from the harness: ' + S.LastError);
  S.Run;
  Check(Norm(T.Output) = '42|', 'unit from the harness runs');
  S.Free; F.Free; T.Free;

  S := Fresh(T, F);
  S.AddUnit('Hello', 'unit Hello; interface procedure Say; implementation procedure Say; begin writeln(''hi'') end; begin writeln(''init'') end.');
  Check(S.LoadSource('program t; uses Hello; begin Say end.'), 'AddUnit: ' + S.LastError);
  S.Run;
  Check(Norm(T.Output) = 'init|hi|', 'AddUnit unit runs after its initialization');
  S.Free; F.Free; T.Free;

  S := Fresh(T, F);
  Check(not S.LoadSource('program t; uses Missing; begin end.'), 'missing unit');
  Check(Pos('Unit file not found: Missing', S.LastError) > 0, 'missing unit message');
  S.Free; F.Free; T.Free;

  { the clock behind GetDate and GetTime }
  S := Fresh(T, F);
  S.Clock := @FixedClock;
  S.LoadSource('program t; uses Dos; var y, m, d, w: word; begin GetDate(y, m, d, w); writeln(y, ''-'', m, ''-'', d, '' '', w) end.');
  S.Run;
  Check(Norm(T.Output) = '2001-2-3 6|', 'session clock: ' + Norm(T.Output));
  S.Free; F.Free; T.Free;

  { parameters }
  S := Fresh(T, F);
  S.Params.Add('one');
  S.Params.Add('two');
  S.LoadSource('program t; begin writeln(paramcount, '' '', paramstr(1), '' '', paramstr(2)) end.');
  S.Run;
  Check(Norm(T.Output) = '2 one two|', 'parameters: ' + Norm(T.Output));
  S.Free; F.Free; T.Free;

  { two sessions at once do not share anything }
  S := Fresh(T, F);
  S.LoadSource('program t; var x: integer; begin x := 5; writeln(x) end.');
  Txt := '';
  S.Run;
  Txt := T.Output;
  S.Run;
  Check(T.Output = Txt + Txt, 'a program can be run again');
  S.Free; F.Free; T.Free;

  { host commands: the registry of the terminal (HostReg) }
  S := Fresh(T, F);
  Check(S.LoadSource('program t; begin writeln(HostCall(''x'')) end.'), 'HostCall compiles');
  St := S.Run;
  Check((St = rsError) and (S.ExitCode = 300) and (Pos('there is no host to ask', T.Output) > 0), 'HostCall without a registry is run-time error 300: ' + Norm(T.Output));
  S.Free; F.Free; T.Free;
  S := Fresh(T, F);
  Demo := THostDemo.Create;
  T.Hosts.Add('demo', 'a demo', 'list', @Demo.Handle);
  S.LoadSource('program t; var n, i, c: integer; s: string; begin Val(HostCall(''demo.list''), n, c);' +
    ' for i := 1 to n do writeln(HostCall(''field '' + chr(48 + i) + '' name''), ''/'', HostCall(''field '' + chr(48 + i) + '' n''));' +
    ' writeln(HostCall(''=demo.list'')); writeln(HostCall(''host.list'')); end.');
  St := S.Run;
  Check((St = rsEnd) and (Pos('alpha/1', T.Output) > 0) and (Pos('beta/2', T.Output) > 0), 'a provider of the terminal answers: ' + Norm(T.Output));
  S.Free; F.Free; T.Free;
  S := Fresh(T, F);
  T.Hosts.Add('demo', 'a demo', 'list', @Demo.Handle);
  S.LoadSource('program t; begin writeln(HostCall(''demo.nope'')) end.');
  St := S.Run;
  Check((St = rsError) and (Pos('no such demo command', T.Output) > 0), 'an error of the provider is run-time error 300 with its text: ' + Norm(T.Output));
  S.Free; F.Free; T.Free;
  Demo.Free;
  WriteLn(Total - Failures, ' of ', Total, ' API checks passed');
  if Failures > 0 then Halt(1);
end.
