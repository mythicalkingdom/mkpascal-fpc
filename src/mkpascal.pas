unit mkpascal;
// MKPascal: a Turbo Pascal style interpreter you can embed.
//
//   Session := TMKSession.Create(Term, Files);     // Term: TMKTerm (screen/keyboard), Files: TMKFiles (file harness)
//   if Session.LoadSource(Text) then
//     Status := Session.Run
//   else
//     Term.Write(Session.LastError);
//
// Every session has its own memory, terminal and file harness, so a server can run many at once (one
// thread each).  RequestBreak may be called from another thread; limits stop runaway programs.
{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, mkp_defs, mkp_harness, mkp_lexer, mkp_types, mkp_mem, mkp_run, mkp_nodes, mkp_compiler;

type
  TMKRunStatus = (rsEnd, rsHalt, rsError, rsLimit, rsBreak);

  TMKSession = class
  private
    FTerm: TMKTerm;
    FFiles: TMKFiles;
    FImage: TProgramImage;
    FIncludes: TStringList;
    FUnits: TStringList;
    FDefines: TStringList;
    FParams: TStringList;
    FLastError: string;
    FExitCode: Integer;
    FBreak: Boolean;
    FRun: TRun;
    FOnYield: TThreadMethod;
    function IncludeText(const Name: string; out Text: string): Boolean;
    function UnitText(const Name: string; out Text: string): Boolean;
    procedure DoYield;
  public
    // limits (0 = no limit)
    MemoryBytes: LongWord;        // size of the Pascal memory: globals + heap + stack (default 4 MB)
    StackBytes: LongWord;         // part of it used for the stack (default 512 KB)
    MaxSteps: Int64;              // loop iterations and routine calls
    MaxRuntimeMs: Int64;          // run time, not counting time spent waiting for input
    MaxOutputChars: Int64;
    MaxFileBytes: Int64;
    MaxOpenFiles: Integer;
    MaxCallDepth: Integer;
    Clock: TMKClock;              // time of day for GetDate/GetTime (default: the real clock)
    constructor Create(ATerm: TMKTerm; AFiles: TMKFiles);
    destructor Destroy; override;
    procedure AddInclude(const Name, Text: string);        // text for an include directive with this file name
    procedure AddUnit(const Name, Text: string);           // source of a unit, found by `uses Name` before the file harness is asked
    procedure Define(const Name: string);                  // a conditional compilation symbol
    { compile; False on error (LastError says why) }
    function LoadSource(const Text: string): Boolean;
    function LoadFile(const Name: string): Boolean;        // read through the file harness
    { run the loaded program to its end }
    function Run: TMKRunStatus;
    procedure RequestBreak;                                 // may be called from another thread
    property LastError: string read FLastError;
    property ExitCode: Integer read FExitCode;
    property Params: TStringList read FParams;
    property Term: TMKTerm read FTerm;
    property Files: TMKFiles read FFiles;
    property OnYield: TThreadMethod read FOnYield write FOnYield;   // called every few thousand steps
  end;

implementation

constructor TMKSession.Create(ATerm: TMKTerm; AFiles: TMKFiles);
begin
  inherited Create;
  FTerm := ATerm;
  FFiles := AFiles;
  FIncludes := TStringList.Create;
  FIncludes.CaseSensitive := False;
  FUnits := TStringList.Create;
  FUnits.CaseSensitive := False;
  FDefines := TStringList.Create;
  FParams := TStringList.Create;
  MemoryBytes := 4 * 1024 * 1024;
  StackBytes := 512 * 1024;
  MaxFileBytes := 16 * 1024 * 1024;
  MaxOpenFiles := 15;
  MaxCallDepth := 10000;
end;

destructor TMKSession.Destroy;
begin
  FImage.Free;
  FIncludes.Free;
  FUnits.Free;
  FDefines.Free;
  FParams.Free;
  inherited Destroy;
end;

procedure TMKSession.AddInclude(const Name, Text: string);
begin
  FIncludes.Values[Name] := '';          // placeholder so IndexOfName finds it
  FIncludes.Add('');
  FIncludes.Delete(FIncludes.Count - 1);
  FIncludes.Values[Name] := StringReplace(Text, #13#10, #1, [rfReplaceAll]);
end;

procedure TMKSession.AddUnit(const Name, Text: string);
begin
  FUnits.Values[Name] := StringReplace(Text, #13#10, #1, [rfReplaceAll]);
end;

{ unit sources: registered text first, then NAME.PAS through the file harness }
function TMKSession.UnitText(const Name: string; out Text: string): Boolean;
var
  I: Integer;
begin
  I := FUnits.IndexOfName(Name);
  if I >= 0 then
  begin
    Text := StringReplace(FUnits.ValueFromIndex[I], #1, #13#10, [rfReplaceAll]);
    Exit(True);
  end;
  try
    Text := FFiles.ReadFile(Name + '.pas');
    Result := True;
  except
    on EMKFile do Result := False;
  end;
end;

procedure TMKSession.Define(const Name: string);
begin
  FDefines.Add(Name);
end;

function TMKSession.IncludeText(const Name: string; out Text: string): Boolean;
var
  I: Integer;
begin
  I := FIncludes.IndexOfName(Name);
  if I >= 0 then
  begin
    Text := StringReplace(FIncludes.ValueFromIndex[I], #1, #13#10, [rfReplaceAll]);
    Exit(True);
  end;
  { through the file harness; a name without an extension also tries .pas, as Turbo Pascal does }
  try
    Text := FFiles.ReadFile(Name);
    Exit(True);
  except
    on EMKFile do ;
  end;
  if Pos('.', Name) = 0 then
    try
      Text := FFiles.ReadFile(Name + '.pas');
      Exit(True);
    except
      on EMKFile do ;
    end;
  Result := False;
end;

function TMKSession.LoadSource(const Text: string): Boolean;
var
  C: TCompiler;
  MaxG: LongWord;
begin
  FreeAndNil(FImage);
  FLastError := '';
  MaxG := MemoryBytes div 2;
  C := TCompiler.Create(@IncludeText, @UnitText, FDefines, MaxG);
  try
    try
      FImage := C.Compile(Text);
      Result := True;
    except
      on E: EMKCompile do
      begin
        FLastError := 'Error: ' + E.Message + ' (';
        if E.InUnit <> '' then FLastError := FLastError + 'unit ' + E.InUnit + ', ';
        if E.FileName <> '' then FLastError := FLastError + 'file ' + E.FileName + ', ';
        FLastError := FLastError + 'line ' + IntToStr(E.Line) + ', column ' + IntToStr(E.Col) + ')';
        Result := False;
      end;
    end;
  finally
    C.Free;
  end;
end;

function TMKSession.LoadFile(const Name: string): Boolean;
var
  Text: string;
begin
  try
    Text := FFiles.ReadFile(Name);
  except
    on E: EMKFile do
    begin
      FLastError := 'Error: cannot read ' + Name;
      Exit(False);
    end;
  end;
  Result := LoadSource(Text);
end;

procedure TMKSession.RequestBreak;
begin
  FBreak := True;
  if FRun <> nil then FRun.BreakFlag := True;
end;

procedure TMKSession.DoYield;
begin
  if Assigned(FOnYield) then FOnYield();
end;

function TMKSession.Run: TMKRunStatus;
var
  Mem: TMem;
  R: TRun;
  Stack: LongWord;
  Where: string;
begin
  Result := rsEnd;
  FExitCode := 0;
  if FImage = nil then Exit(rsError);
  Stack := StackBytes;
  if Stack > MemoryBytes div 2 then Stack := MemoryBytes div 2;
  Mem := TMem.Create(MemoryBytes);
  R := TRun.Create(Mem, FTerm, FFiles);
  try
    FRun := R;
    Mem.Fill(16, FImage.GlobalEnd - 16, 0);
    Mem.InitHeap(FImage.GlobalEnd + 16, MemoryBytes - Stack);
    Mem.StackBase := MemoryBytes - Stack;
    R.SP := MemoryBytes;
    R.FP := 0;
    R.MaxDepth := MaxCallDepth;
    R.Limits.MaxSteps := MaxSteps;
    R.Limits.MaxRuntimeMs := MaxRuntimeMs;
    R.Limits.MaxOutputChars := MaxOutputChars;
    R.Limits.MaxFileBytes := MaxFileBytes;
    R.Limits.MaxOpenFiles := MaxOpenFiles;
    R.Params.Assign(FParams);
    R.OnYield := @DoYield;
    R.Clock := Clock;
    FImage.Install(R);
    R.StartClock;
    if FBreak then begin FBreak := False; R.BreakFlag := True; end;
    try
      try
        FImage.Main.Run(R);
      except
        on E: EMKHalt do
        begin
          Result := rsHalt;
          FExitCode := E.Code;
        end;
        on E: EMKRuntime do
        begin
          Result := rsError;
          FExitCode := E.Code;
          FTerm.Write(#13#10'Runtime error ' + IntToStr(E.Code) + ': ' + E.Message + ' at line ' + IntToStr(R.LineNo) + '.'#13#10);
        end;
        on E: EMKLimit do
        begin
          Result := rsLimit;
          FTerm.Write(#13#10 + E.Message + #13#10);
        end;
        on E: EMKBreak do
        begin
          Result := rsBreak;
          FTerm.Write(#13#10'Program interrupted at line ' + IntToStr(R.LineNo) + '.'#13#10);
        end;
        on E: Exception do
        begin
          Result := rsError;
          FTerm.Write(#13#10'Internal error: ' + E.Message + #13#10);
        end;
      end;
    finally
      R.CloseAllFiles;
    end;
  finally
    FRun := nil;
    R.Free;
    Mem.Free;
  end;
end;

end.
