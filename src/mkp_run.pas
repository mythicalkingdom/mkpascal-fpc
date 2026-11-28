{ SPDX-License-Identifier: GPL-3.0-or-later }
unit mkp_run;
// Run time state and services: the memory, stack pointers, console input, Pascal files on top of the
// file harness, limits, break handling, Random and number formatting.
{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, contnrs, DateUtils, Math, mkp_defs, mkp_types, mkp_mem, mkp_harness;

type
  TFileMode = (fmClosed, fmIn, fmOut, fmInOut);
  TConsoleKind = (ckNone, ckAny, ckIn, ckOut, ckLst);

  TPFile = class
  public
    Name: string;
    Assigned: Boolean;
    Mode: TFileMode;
    IsText: Boolean;
    RecSize: Integer;
    Data: RawByteString;
    Len, Pos: Integer;
    Dirty: Boolean;
    Console: TConsoleKind;
    HasPending: Boolean;
    PendingTime: TDateTime;
  end;

  TLimits = record
    MaxSteps: Int64;          // loop iterations and routine calls, 0 = no limit
    MaxRuntimeMs: Int64;
    MaxOutputChars: Int64;
    MaxFileBytes: Int64;
    MaxOpenFiles: Integer;
  end;

  TRun = class
  private
    FFiles: TObjectList;          // handle - 1 -> TPFile
    FStartTick: QWord;
    FWaitedMs: Int64;
    procedure NewFileHandle(F: TPFile; out Handle: Integer);
    procedure Load(F: TPFile);
    procedure EnsureCap(F: TPFile; N: Integer);
    function ReadFileToken(F: TPFile): string;
  public
    Mem: TMem;
    Term: TMKTerm;
    Harness: TMKFiles;
    SP, FP: TAddr;
    StackTop: TAddr;
    Depth, MaxDepth: Integer;
    Limits: TLimits;
    Ticks, TotalSteps: Int64;
    BreakFlag: Boolean;
    OutCount: Int64;
    IOResult: Integer;
    Failed: Boolean;
    OnYield: procedure of object;
    // console input
    InBuf: RawByteString;
    InPos: Integer;
    InValid: Boolean;
    // standard files and Random
    RandSeed: LongWord;
    Params: TStringList;
    ProgramName: string;
    LineNo: Integer;               // line of the statement being run (for error messages)
    Crt_Fg, Crt_Bg: Integer;
    KeyBuf: RawByteString;
    OpenFiles: Integer;
    StdIn, StdOut, StdLst: TPFile;      // handles 1, 2 and 3
    ObjTypes: TList;                    // object types by VMT id - 1 (set by the program image)
    ProcTable: TList;                   // routines whose address was taken, by procedural value - 1
    GotoLabel: Integer;                 // the label a goto is looking for
    Clock: function: TDateTime;         // time of day for GetDate/GetTime (default: Now)
    DosErrorAddr: TAddr;                // address of the DosError variable (0 if none)
    FSearches: TObjectList;             // FindFirst/FindNext state
    constructor Create(AMem: TMem; ATerm: TMKTerm; AFiles: TMKFiles);
    destructor Destroy; override;
    procedure StartClock;
    procedure Tick; inline;
    procedure CheckLimits;
    procedure Out(const S: RawByteString);
    { console }
    procedure FillLine;
    function ReadToken: string;
    function ConsoleInt: Int64;
    function ConsoleReal: Double;
    function ConsoleChar: Integer;
    function ConsoleStr(MaxLen: Integer): ShortString;
    procedure ConsoleLnEnd;
    function ConsoleEoln: Boolean;
    function ReadKey: Integer;
    function KeyPressed: Boolean;
    procedure Delay(Ms: Integer);
    { file variables: the first four bytes of a file variable hold a handle }
    function FileAt(A: TAddr; CreateIt: Boolean): TPFile;
    procedure SetStdFile(A: TAddr; Kind: TConsoleKind);
    procedure AssignFile(A: TAddr; const AName: string; AIsText: Boolean);
    procedure ResetFile(F: TPFile; RecSize: Integer; Typed: Boolean);
    procedure RewriteFile(F: TPFile; RecSize: Integer; Typed: Boolean);
    procedure AppendFile(F: TPFile);
    procedure FlushFile(F: TPFile);
    procedure CloseFile(F: TPFile; Quiet: Boolean);
    procedure CloseAllFiles;
    procedure EraseFile(F: TPFile);
    procedure RenameFile(F: TPFile; const NewName: string);
    procedure NeedOpen(F: TPFile);
    { text files }
    procedure WriteText(F: TPFile; const S: RawByteString);
    function TextInt(F: TPFile): Int64;
    function TextReal(F: TPFile): Double;
    function TextChar(F: TPFile): Integer;
    function TextStr(F: TPFile; MaxLen: Integer): ShortString;
    procedure TextLnEnd(F: TPFile);
    function FileEof(F: TPFile): Boolean;
    function FileEoln(F: TPFile): Boolean;
    function SeekEof(F: TPFile): Boolean;
    function SeekEoln(F: TPFile): Boolean;
    { typed and untyped files }
    procedure ReadRecord(F: TPFile; Dst: TAddr);
    procedure WriteRecord(F: TPFile; Src: TAddr);
    function BlockRead(F: TPFile; Dst: TAddr; Count: Integer): Integer;
    function BlockWrite(F: TPFile; Src: TAddr; Count: Integer): Integer;
    procedure SeekRec(F: TPFile; N: Int64);
    function FilePos(F: TPFile): Int64;
    function FileSize(F: TPFile): Int64;
    procedure TruncateFile(F: TPFile);
    procedure SetFileTime(F: TPFile; T: TDateTime);
    function GetFileTime(F: TPFile): TDateTime;
    { Dos }
    function TimeNow: TDateTime;
    procedure SetDosError(E: Integer);
    procedure FindFirstFile(const Pattern: string; Sr: TAddr);
    procedure FindNextFile(Sr: TAddr);
    { Random (the Turbo Pascal generator) }
    function RandomInt(N: Int64): Int64;
    function RandomReal: Double;
    procedure Randomize;
  end;

const
  NoWidth = Low(Integer);          // no field width given in a Write argument

function FmtInt(V: Int64; W: Integer): string;
function FmtReal(V: Double; W, D: Integer): string;
function FmtPad(const S: string; W: Integer): string;
function ParseReal(const S: string; out V: Double): Boolean;
function PackDosTime(D: TDateTime): LongInt;
function UnpackDosTime(P: LongInt): TDateTime;

var
  FS: TFormatSettings;

implementation

function HarnessCode(E: EMKFile): Integer;
begin
  if E.Code = 'ENOENT' then Result := 2
  else if (E.Code = 'ENOTDIR') or (E.Code = 'EINVAL') then Result := 3
  else if (E.Code = 'EACCES') or (E.Code = 'EEXIST') or (E.Code = 'EPERM') then Result := 5
  else Result := 101;
end;

{ ---------------- formatting ---------------- }

function FmtPad(const S: string; W: Integer): string;
begin
  if W = NoWidth then Exit(S);
  if W < 0 then
  begin
    if Length(S) >= -W then Result := S else Result := S + StringOfChar(' ', -W - Length(S));
  end
  else if Length(S) >= W then Result := S
  else Result := StringOfChar(' ', W - Length(S)) + S;
end;

function FmtInt(V: Int64; W: Integer): string;
begin
  Result := FmtPad(IntToStr(V), W);
end;

function SciFormat(V: Double; W: Integer): string;
var
  Digits, P, Ex: Integer;
  S, Mant, ExpS, Sign: string;
begin
  Digits := 10;
  if W <> NoWidth then
  begin
    Digits := W - 7;
    if Digits < 1 then Digits := 1;
    if Digits > 15 then Digits := 15;
  end;
  if V < 0 then Sign := '-' else Sign := ' ';
  if V = 0 then Exit(Sign + '0.' + StringOfChar('0', Digits) + 'E+00');
  S := Format('%.*e', [Digits + 1, Abs(V)], FS);          // 1.2345678901E+002
  P := Pos('E', UpperCase(S));
  Mant := Copy(S, 1, P - 1);
  Ex := StrToInt(Copy(S, P + 1, MaxInt));
  if Ex < 0 then ExpS := '-' else ExpS := '+';
  ExpS := ExpS + Format('%.2d', [Abs(Ex)]);
  Result := Sign + Mant + 'E' + ExpS;
end;

function FmtReal(V: Double; W, D: Integer): string;
begin
  if IsInfinite(V) or IsNan(V) then V := 1.7e38;
  if D < 0 then Exit(FmtPad(SciFormat(V, W), W));
  if D > 24 then D := 24;
  if Abs(V) < 1e21 then Result := Format('%.*f', [D, V], FS) else Result := Format('%.*e', [D + 1, V], FS);
  if (Length(Result) > 1) and (Result[1] = '-') and (StrToFloatDef(Result, 1, FS) = 0) then Delete(Result, 1, 1);
  Result := FmtPad(Result, W);
end;

function ParseReal(const S: string; out V: Double): Boolean;
var
  I, N: Integer;
  SawDigit: Boolean;
begin
  Result := False;
  N := Length(S);
  if N = 0 then Exit;
  I := 1;
  if S[I] in ['+', '-'] then Inc(I);
  SawDigit := False;
  while (I <= N) and (S[I] in ['0'..'9']) do begin Inc(I); SawDigit := True; end;
  if (I <= N) and (S[I] = '.') then
  begin
    Inc(I);
    while (I <= N) and (S[I] in ['0'..'9']) do begin Inc(I); SawDigit := True; end;
  end;
  if not SawDigit then Exit;
  if (I <= N) and (S[I] in ['e', 'E']) then
  begin
    Inc(I);
    if (I <= N) and (S[I] in ['+', '-']) then Inc(I);
    if (I > N) or not (S[I] in ['0'..'9']) then Exit;
    while (I <= N) and (S[I] in ['0'..'9']) do Inc(I);
  end;
  if I <= N then Exit;
  Result := TryStrToFloat(S, V, FS);
end;

function PackDosTime(D: TDateTime): LongInt;
var
  Y, Mo, Dd, H, Mi, S, Ms: Word;
  Year: Integer;
  Time, Date: LongWord;
begin
  DecodeDateTime(D, Y, Mo, Dd, H, Mi, S, Ms);
  Year := Y;
  if Year < 1980 then Year := 1980;
  if Year > 2107 then Year := 2107;
  Time := (H shl 11) or (Mi shl 5) or (S shr 1);
  Date := ((Year - 1980) shl 9) or (Mo shl 5) or Dd;
  Result := LongInt((Date shl 16) or Time);
end;

function UnpackDosTime(P: LongInt): TDateTime;
var
  U: LongWord;
  Mo, Dd: Integer;
begin
  U := LongWord(P);
  Mo := (U shr 21) and 15;
  Dd := (U shr 16) and 31;
  if Mo < 1 then Mo := 1;
  if Dd < 1 then Dd := 1;
  if not TryEncodeDateTime(((U shr 25) and 127) + 1980, Mo, Dd, (U shr 11) and 31, (U shr 5) and 63, (U and 31) * 2, 0, Result) then
    Result := 0;
end;

{ ---------------- TRun ---------------- }

constructor TRun.Create(AMem: TMem; ATerm: TMKTerm; AFiles: TMKFiles);
begin
  inherited Create;
  Mem := AMem;
  Term := ATerm;
  Harness := AFiles;
  FFiles := TObjectList.Create(True);
  FSearches := TObjectList.Create(True);
  Params := TStringList.Create;
  Limits.MaxFileBytes := 16 * 1024 * 1024;
  Limits.MaxOpenFiles := 15;
  MaxDepth := 10000;
  Crt_Fg := 7;
  RandSeed := 0;
  StdIn := TPFile.Create;
  StdOut := TPFile.Create;
  StdLst := TPFile.Create;
  StdIn.Console := ckIn;
  StdOut.Console := ckOut;
  StdLst.Console := ckLst;
  StdIn.IsText := True;
  StdOut.IsText := True;
  StdLst.IsText := True;
  StdIn.Assigned := True;
  StdOut.Assigned := True;
  StdLst.Assigned := True;
  FFiles.Add(StdIn);
  FFiles.Add(StdOut);
  FFiles.Add(StdLst);
end;

destructor TRun.Destroy;
begin
  FFiles.Free;
  FSearches.Free;
  Params.Free;
  inherited Destroy;
end;

procedure TRun.StartClock;
begin
  FStartTick := GetTickCount64;
  FWaitedMs := 0;
  Ticks := 0;
  TotalSteps := 0;
  OutCount := 0;
  BreakFlag := False;
end;

procedure TRun.CheckLimits;
begin
  TotalSteps := TotalSteps + Ticks;
  Ticks := 0;
  if BreakFlag then
  begin
    BreakFlag := False;
    raise EMKBreak.Create('break');
  end;
  if (Limits.MaxSteps > 0) and (TotalSteps > Limits.MaxSteps) then raise EMKLimit.Create('Step limit exceeded');
  if (Limits.MaxRuntimeMs > 0) and (Int64(GetTickCount64 - FStartTick) - FWaitedMs > Limits.MaxRuntimeMs) then
    raise EMKLimit.Create('Time limit exceeded');
  if Assigned(OnYield) then OnYield();
end;

procedure TRun.Tick;
begin
  Inc(Ticks);
  if Ticks >= 2048 then CheckLimits;
end;

procedure TRun.Out(const S: RawByteString);
begin
  if Limits.MaxOutputChars > 0 then
  begin
    Inc(OutCount, Length(S));
    if OutCount > Limits.MaxOutputChars then raise EMKLimit.Create('Output limit exceeded');
  end;
  Term.Write(S);
end;

{ ---------------- console ---------------- }

procedure TRun.FillLine;
var
  T0: QWord;
  L: RawByteString;
  Got: Boolean;
begin
  if InValid then Exit;
  T0 := GetTickCount64;
  Got := Term.ReadLine(L);
  Inc(FWaitedMs, GetTickCount64 - T0);
  if not Got then L := '';
  if not Term.LineEndEchoed then Out(#13#10);
  InBuf := L;
  InPos := 1;
  InValid := True;
end;

function TRun.ReadToken: string;
var
  S: Integer;
begin
  while True do
  begin
    FillLine;
    while (InPos <= Length(InBuf)) and (InBuf[InPos] in [' ', #9]) do Inc(InPos);
    if InPos > Length(InBuf) then begin InValid := False; Continue; end;
    S := InPos;
    while (InPos <= Length(InBuf)) and not (InBuf[InPos] in [' ', #9]) do Inc(InPos);
    Exit(Copy(InBuf, S, InPos - S));
  end;
end;

function TRun.ConsoleInt: Int64;
var
  T: string;
begin
  T := ReadToken;
  if (T <> '') and (T[1] = '$') then
  begin
    if TryStrToInt64(T, Result) then Exit;
  end
  else if TryStrToInt64(T, Result) and (T[1] in ['0'..'9', '+', '-']) then Exit;
  InValid := False;
  raise EMKRuntime.CreateCode(106);
end;

function TRun.ConsoleReal: Double;
var
  T: string;
begin
  T := ReadToken;
  if ParseReal(T, Result) then Exit;
  InValid := False;
  raise EMKRuntime.CreateCode(106);
end;

function TRun.ConsoleChar: Integer;
begin
  FillLine;
  if InPos > Length(InBuf) then begin InValid := False; Exit(13); end;
  Result := Ord(InBuf[InPos]);
  Inc(InPos);
end;

function TRun.ConsoleStr(MaxLen: Integer): ShortString;
var
  S: RawByteString;
begin
  FillLine;
  S := Copy(InBuf, InPos, MaxInt);
  InPos := Length(InBuf) + 1;
  if Length(S) > MaxLen then S := Copy(S, 1, MaxLen);
  Result := S;
end;

procedure TRun.ConsoleLnEnd;
begin
  if not InValid then FillLine;
  InValid := False;
end;

function TRun.ConsoleEoln: Boolean;
begin
  Result := InValid and (InPos > Length(InBuf));
end;

function TRun.ReadKey: Integer;
var
  T0: QWord;
begin
  if KeyBuf <> '' then
  begin
    Result := Ord(KeyBuf[1]);
    Delete(KeyBuf, 1, 1);
    Exit;
  end;
  T0 := GetTickCount64;
  Result := Term.ReadKey;
  Inc(FWaitedMs, GetTickCount64 - T0);
  if Result < 0 then Result := 13;
end;

function TRun.KeyPressed: Boolean;
begin
  Result := (KeyBuf <> '') or Term.KeyPressed;
end;

procedure TRun.Delay(Ms: Integer);
var
  Left: Integer;
begin
  Left := Ms;
  while Left > 0 do
  begin
    if BreakFlag then CheckLimits;
    if Left > 50 then begin Sleep(50); Dec(Left, 50); end else begin Sleep(Left); Left := 0; end;
    Inc(FWaitedMs, 50);
  end;
end;

{ ---------------- file variables ---------------- }

procedure TRun.NewFileHandle(F: TPFile; out Handle: Integer);
begin
  FFiles.Add(F);
  Handle := FFiles.Count;
end;

function TRun.FileAt(A: TAddr; CreateIt: Boolean): TPFile;
var
  H: Integer;
begin
  H := Mem.GetInt(A, 4, False);
  if (H = 0) or (H > FFiles.Count) then
  begin
    if not CreateIt then Exit(nil);
    Result := TPFile.Create;
    NewFileHandle(Result, H);
    Mem.PutInt(A, 4, H);
  end
  else
    Result := TPFile(FFiles[H - 1]);
end;

procedure TRun.SetStdFile(A: TAddr; Kind: TConsoleKind);
begin
  case Kind of
    ckIn: Mem.PutInt(A, 4, 1);
    ckLst: Mem.PutInt(A, 4, 3);
  else
    Mem.PutInt(A, 4, 2);
  end;
end;

procedure TRun.NeedOpen(F: TPFile);
begin
  if F = nil then raise EMKRuntime.CreateCode(102);
  if F.Console <> ckNone then Exit;
  if F.Mode = fmClosed then
  begin
    if F.Assigned then raise EMKRuntime.CreateCode(103) else raise EMKRuntime.CreateCode(102);
  end;
end;

procedure TRun.AssignFile(A: TAddr; const AName: string; AIsText: Boolean);
var
  F: TPFile;
begin
  F := FileAt(A, True);
  if (F.Mode <> fmClosed) and (F.Console = ckNone) then CloseFile(F, True);
  F.Name := AName;
  F.Assigned := True;
  F.IsText := AIsText;
  F.Mode := fmClosed;
  F.Console := ckNone;
  F.Data := '';
  F.Len := 0;
  F.Pos := 0;
  F.Dirty := False;
  F.HasPending := False;
  if AName = '' then F.Console := ckAny;
end;

procedure TRun.EnsureCap(F: TPFile; N: Integer);
var
  Cap: Integer;
begin
  if (Limits.MaxFileBytes > 0) and (N > Limits.MaxFileBytes) then raise EMKRuntime.CreateCode(101);
  Cap := Length(F.Data);
  if N > Cap then
  begin
    Cap := Cap * 2;
    if Cap < N then Cap := N;
    if Cap < 256 then Cap := 256;
    SetLength(F.Data, Cap);
  end;
end;

procedure TRun.Load(F: TPFile);
begin
  try
    F.Data := Harness.ReadFile(F.Name);
  except
    on E: EMKFile do raise EMKRuntime.CreateCode(HarnessCode(E));
  end;
  if (Limits.MaxFileBytes > 0) and (Length(F.Data) > Limits.MaxFileBytes) then raise EMKRuntime.CreateCode(100);
  F.Len := Length(F.Data);
end;

procedure TRun.ResetFile(F: TPFile; RecSize: Integer; Typed: Boolean);
begin
  if (F = nil) or not F.Assigned then raise EMKRuntime.CreateCode(102);
  if F.Console <> ckNone then Exit;
  if F.Mode <> fmClosed then CloseFile(F, False);
  if (Limits.MaxOpenFiles > 0) and (OpenFiles >= Limits.MaxOpenFiles) then raise EMKRuntime.CreateCode(4);
  Load(F);
  F.Pos := 0;
  F.Dirty := False;
  if F.IsText then F.Mode := fmIn else F.Mode := fmInOut;
  F.RecSize := RecSize;
  Inc(OpenFiles);
end;

procedure TRun.RewriteFile(F: TPFile; RecSize: Integer; Typed: Boolean);
begin
  if (F = nil) or not F.Assigned then raise EMKRuntime.CreateCode(102);
  if F.Console <> ckNone then Exit;
  if F.Mode <> fmClosed then CloseFile(F, False);
  if (Limits.MaxOpenFiles > 0) and (OpenFiles >= Limits.MaxOpenFiles) then raise EMKRuntime.CreateCode(4);
  F.Data := '';
  F.Len := 0;
  F.Pos := 0;
  if F.IsText then F.Mode := fmOut else F.Mode := fmInOut;
  F.Dirty := True;
  F.RecSize := RecSize;
  Inc(OpenFiles);
  try
    FlushFile(F);                       // fail early when the name cannot be created
  except
    Dec(OpenFiles);
    F.Mode := fmClosed;
    raise;
  end;
end;

procedure TRun.AppendFile(F: TPFile);
begin
  if (F = nil) or not F.Assigned then raise EMKRuntime.CreateCode(102);
  if F.Console <> ckNone then Exit;
  if not F.IsText then raise EMKRuntime.CreateCode(105);
  if F.Mode <> fmClosed then CloseFile(F, False);
  if (Limits.MaxOpenFiles > 0) and (OpenFiles >= Limits.MaxOpenFiles) then raise EMKRuntime.CreateCode(4);
  Load(F);
  F.Pos := F.Len;
  F.Mode := fmOut;
  F.Dirty := False;
  Inc(OpenFiles);
end;

procedure TRun.FlushFile(F: TPFile);
begin
  if (F = nil) or (F.Console <> ckNone) or (F.Mode = fmClosed) or not F.Dirty then Exit;
  try
    Harness.WriteFile(F.Name, Copy(F.Data, 1, F.Len));
    F.Dirty := False;
    if F.HasPending then
      try Harness.SetTime(F.Name, F.PendingTime); except on EMKFile do ; end;
  except
    on E: EMKFile do raise EMKRuntime.CreateCode(HarnessCode(E));
  end;
end;

procedure TRun.CloseFile(F: TPFile; Quiet: Boolean);
begin
  if F = nil then
  begin
    if Quiet then Exit;
    raise EMKRuntime.CreateCode(102);
  end;
  if F.Console <> ckNone then Exit;
  if F.Mode = fmClosed then
  begin
    if Quiet then Exit;
    if F.Assigned then raise EMKRuntime.CreateCode(103) else raise EMKRuntime.CreateCode(102);
  end;
  try
    FlushFile(F);
  finally
    F.Mode := fmClosed;
    F.Data := '';
    F.Len := 0;
    F.Pos := 0;
    F.Dirty := False;
    F.HasPending := False;
    Dec(OpenFiles);
  end;
end;

procedure TRun.CloseAllFiles;
var
  I: Integer;
begin
  for I := 0 to FFiles.Count - 1 do
    try
      CloseFile(TPFile(FFiles[I]), True);
    except
      on Exception do ;
    end;
end;

procedure TRun.EraseFile(F: TPFile);
begin
  if (F = nil) or not F.Assigned then raise EMKRuntime.CreateCode(102);
  if F.Mode <> fmClosed then raise EMKRuntime.CreateCode(5);
  try
    Harness.Remove(F.Name);
  except
    on E: EMKFile do raise EMKRuntime.CreateCode(HarnessCode(E));
  end;
end;

procedure TRun.RenameFile(F: TPFile; const NewName: string);
begin
  if (F = nil) or not F.Assigned then raise EMKRuntime.CreateCode(102);
  if F.Mode <> fmClosed then raise EMKRuntime.CreateCode(5);
  try
    Harness.Rename(F.Name, NewName);
  except
    on E: EMKFile do raise EMKRuntime.CreateCode(HarnessCode(E));
  end;
  F.Name := NewName;
end;

procedure TRun.SetFileTime(F: TPFile; T: TDateTime);
begin
  NeedOpen(F);
  if F.Console <> ckNone then raise EMKRuntime.CreateCode(103);
  F.HasPending := True;
  F.PendingTime := T;
  if not F.Dirty then
    try Harness.SetTime(F.Name, T); except on E: EMKFile do raise EMKRuntime.CreateCode(HarnessCode(E)); end;
end;

function TRun.GetFileTime(F: TPFile): TDateTime;
var
  Sz: Int64;
begin
  NeedOpen(F);
  if F.Console <> ckNone then raise EMKRuntime.CreateCode(103);
  if F.HasPending then Exit(F.PendingTime);
  if F.Dirty or not Harness.HasDates then Exit(Now);
  try
    Harness.Stat(F.Name, Sz, Result);
  except
    on E: EMKFile do
      if E.Code = 'ENOENT' then Result := Now else raise EMKRuntime.CreateCode(HarnessCode(E));
  end;
end;

{ ---------------- text files ---------------- }

procedure TRun.WriteText(F: TPFile; const S: RawByteString);
var
  N: Integer;
begin
  if F = nil then raise EMKRuntime.CreateCode(102);
  case F.Console of
    ckAny, ckOut: begin Out(S); Exit; end;
    ckLst:
      begin
        if not Term.HasPrinter then raise EMKRuntime.CreateCode(5);
        Term.PrinterWrite(S);
        Exit;
      end;
    ckIn: raise EMKRuntime.CreateCode(105);
  end;
  NeedOpen(F);
  if F.Mode <> fmOut then raise EMKRuntime.CreateCode(105);
  N := Length(S);
  if N = 0 then Exit;
  EnsureCap(F, F.Pos + N);
  Move(S[1], F.Data[F.Pos + 1], N);
  Inc(F.Pos, N);
  if F.Pos > F.Len then F.Len := F.Pos;
  F.Dirty := True;
end;

function TRun.ReadFileToken(F: TPFile): string;
var
  S: Integer;
begin
  while (F.Pos < F.Len) and (Byte(F.Data[F.Pos + 1]) <= 32) do Inc(F.Pos);
  S := F.Pos;
  while (F.Pos < F.Len) and (Byte(F.Data[F.Pos + 1]) > 32) do Inc(F.Pos);
  Result := Copy(F.Data, S + 1, F.Pos - S);
end;

function TRun.TextInt(F: TPFile): Int64;
var
  T: string;
begin
  if F = nil then raise EMKRuntime.CreateCode(102);
  if F.Console in [ckAny, ckIn] then Exit(ConsoleInt);
  NeedOpen(F);
  if F.Mode <> fmIn then raise EMKRuntime.CreateCode(104);
  T := ReadFileToken(F);
  if T = '' then Exit(0);
  if TryStrToInt64(T, Result) and (T[1] in ['0'..'9', '+', '-', '$']) then Exit;
  raise EMKRuntime.CreateCode(106);
end;

function TRun.TextReal(F: TPFile): Double;
var
  T: string;
begin
  if F = nil then raise EMKRuntime.CreateCode(102);
  if F.Console in [ckAny, ckIn] then Exit(ConsoleReal);
  NeedOpen(F);
  if F.Mode <> fmIn then raise EMKRuntime.CreateCode(104);
  T := ReadFileToken(F);
  if T = '' then Exit(0);
  if ParseReal(T, Result) then Exit;
  raise EMKRuntime.CreateCode(106);
end;

function TRun.TextChar(F: TPFile): Integer;
begin
  if F = nil then raise EMKRuntime.CreateCode(102);
  if F.Console in [ckAny, ckIn] then Exit(ConsoleChar);
  NeedOpen(F);
  if F.Mode <> fmIn then raise EMKRuntime.CreateCode(104);
  if F.Pos >= F.Len then Exit(26);
  Result := Byte(F.Data[F.Pos + 1]);
  Inc(F.Pos);
end;

function TRun.TextStr(F: TPFile; MaxLen: Integer): ShortString;
var
  S: Integer;
begin
  if F = nil then raise EMKRuntime.CreateCode(102);
  if F.Console in [ckAny, ckIn] then Exit(ConsoleStr(MaxLen));
  NeedOpen(F);
  if F.Mode <> fmIn then raise EMKRuntime.CreateCode(104);
  S := F.Pos;
  while (F.Pos < F.Len) and not (Byte(F.Data[F.Pos + 1]) in [10, 13, 26]) and (F.Pos - S < MaxLen) do Inc(F.Pos);
  Result := Copy(F.Data, S + 1, F.Pos - S);
end;

procedure TRun.TextLnEnd(F: TPFile);
begin
  if F = nil then raise EMKRuntime.CreateCode(102);
  if F.Console in [ckAny, ckIn] then begin ConsoleLnEnd; Exit; end;
  NeedOpen(F);
  if F.Mode <> fmIn then raise EMKRuntime.CreateCode(104);
  while (F.Pos < F.Len) and not (Byte(F.Data[F.Pos + 1]) in [10, 13]) do Inc(F.Pos);
  if (F.Pos < F.Len) and (Byte(F.Data[F.Pos + 1]) = 13) then Inc(F.Pos);
  if (F.Pos < F.Len) and (Byte(F.Data[F.Pos + 1]) = 10) then Inc(F.Pos);
end;

function TRun.FileEof(F: TPFile): Boolean;
begin
  if F = nil then raise EMKRuntime.CreateCode(102);
  if F.Console <> ckNone then Exit(False);
  NeedOpen(F);
  if F.IsText then
  begin
    if F.Mode <> fmIn then raise EMKRuntime.CreateCode(104);
    Result := (F.Pos >= F.Len) or (Byte(F.Data[F.Pos + 1]) = 26);
  end
  else
    Result := F.Pos >= F.Len;
end;

function TRun.FileEoln(F: TPFile): Boolean;
begin
  if F = nil then raise EMKRuntime.CreateCode(102);
  if F.Console <> ckNone then Exit(ConsoleEoln);
  NeedOpen(F);
  if F.Mode <> fmIn then raise EMKRuntime.CreateCode(104);
  Result := (F.Pos >= F.Len) or (Byte(F.Data[F.Pos + 1]) in [10, 13, 26]);
end;

function TRun.SeekEof(F: TPFile): Boolean;
begin
  if F = nil then raise EMKRuntime.CreateCode(102);
  if F.Console <> ckNone then Exit(False);
  NeedOpen(F);
  if F.Mode <> fmIn then raise EMKRuntime.CreateCode(104);
  while (F.Pos < F.Len) and (Byte(F.Data[F.Pos + 1]) <= 32) and (Byte(F.Data[F.Pos + 1]) <> 26) do Inc(F.Pos);
  Result := (F.Pos >= F.Len) or (Byte(F.Data[F.Pos + 1]) = 26);
end;

function TRun.SeekEoln(F: TPFile): Boolean;
begin
  if F = nil then raise EMKRuntime.CreateCode(102);
  if F.Console <> ckNone then Exit(ConsoleEoln);
  NeedOpen(F);
  if F.Mode <> fmIn then raise EMKRuntime.CreateCode(104);
  while (F.Pos < F.Len) and (Byte(F.Data[F.Pos + 1]) in [32, 9]) do Inc(F.Pos);
  Result := (F.Pos >= F.Len) or (Byte(F.Data[F.Pos + 1]) in [10, 13, 26]);
end;

{ ---------------- typed and untyped files ---------------- }

procedure TRun.ReadRecord(F: TPFile; Dst: TAddr);
begin
  NeedOpen(F);
  if F.IsText or (F.Console <> ckNone) then raise EMKRuntime.CreateCode(103);
  if F.Pos + F.RecSize > F.Len then raise EMKRuntime.CreateCode(100);
  if F.RecSize > 0 then Move(F.Data[F.Pos + 1], Mem.P(Dst, F.RecSize)^, F.RecSize);
  Inc(F.Pos, F.RecSize);
end;

procedure TRun.WriteRecord(F: TPFile; Src: TAddr);
begin
  NeedOpen(F);
  if F.IsText or (F.Console <> ckNone) then raise EMKRuntime.CreateCode(103);
  EnsureCap(F, F.Pos + F.RecSize);
  if F.RecSize > 0 then Move(Mem.P(Src, F.RecSize)^, F.Data[F.Pos + 1], F.RecSize);
  Inc(F.Pos, F.RecSize);
  if F.Pos > F.Len then F.Len := F.Pos;
  F.Dirty := True;
end;

function TRun.BlockRead(F: TPFile; Dst: TAddr; Count: Integer): Integer;
var
  Want, N: Integer;
begin
  NeedOpen(F);
  if F.IsText or (F.Console <> ckNone) then raise EMKRuntime.CreateCode(103);
  Want := Count * F.RecSize;
  N := F.Len - F.Pos;
  if N > Want then N := Want;
  if N < 0 then N := 0;
  if N > 0 then Move(F.Data[F.Pos + 1], Mem.P(Dst, N)^, N);
  Inc(F.Pos, N);
  if F.RecSize > 0 then Result := N div F.RecSize else Result := 0;
end;

function TRun.BlockWrite(F: TPFile; Src: TAddr; Count: Integer): Integer;
var
  N: Integer;
begin
  NeedOpen(F);
  if F.IsText or (F.Console <> ckNone) then raise EMKRuntime.CreateCode(103);
  N := Count * F.RecSize;
  if N > 0 then
  begin
    EnsureCap(F, F.Pos + N);
    Move(Mem.P(Src, N)^, F.Data[F.Pos + 1], N);
    Inc(F.Pos, N);
    if F.Pos > F.Len then F.Len := F.Pos;
    F.Dirty := True;
  end;
  Result := Count;
end;

procedure TRun.SeekRec(F: TPFile; N: Int64);
begin
  NeedOpen(F);
  if F.IsText or (N < 0) then raise EMKRuntime.CreateCode(100);
  F.Pos := Integer(N * F.RecSize);
end;

function TRun.FilePos(F: TPFile): Int64;
begin
  NeedOpen(F);
  if F.IsText then raise EMKRuntime.CreateCode(103);
  Result := F.Pos div F.RecSize;
end;

function TRun.FileSize(F: TPFile): Int64;
begin
  NeedOpen(F);
  if F.IsText then raise EMKRuntime.CreateCode(103);
  Result := F.Len div F.RecSize;
end;

procedure TRun.TruncateFile(F: TPFile);
begin
  NeedOpen(F);
  if F.IsText then raise EMKRuntime.CreateCode(103);
  if F.Pos < F.Len then F.Len := F.Pos;
  F.Dirty := True;
end;

{ ---------------- Dos ---------------- }

function TRun.TimeNow: TDateTime;
begin
  if Assigned(Clock) then Result := Clock() else Result := Now;
end;

procedure TRun.SetDosError(E: Integer);
begin
  if DosErrorAddr <> 0 then Mem.PutInt(DosErrorAddr, 2, E);
end;

function WildMatch(const Pat, Name: string): Boolean;
// * and ? wildcards, not case sensitive
  function M(P, N: Integer): Boolean;
  begin
    while P <= Length(Pat) do
    begin
      if Pat[P] = '*' then
      begin
        for N := N to Length(Name) + 1 do
          if M(P + 1, N) then Exit(True);
        Exit(False);
      end;
      if N > Length(Name) then Exit(False);
      if (Pat[P] <> '?') and (UpCase(Pat[P]) <> UpCase(Name[N])) then Exit(False);
      Inc(P);
      Inc(N);
    end;
    Result := N > Length(Name);
  end;
begin
  Result := M(1, 1);
end;

// SearchRec layout (Turbo Pascal): Fill[1..21] (handle, index), Attr at 21, Time at 22, Size at 26, Name at 30
procedure TRun.FindFirstFile(const Pattern: string; Sr: TAddr);
var
  L, All: TStringList;
  I, Slash: Integer;
  Pat: string;
begin
  Pat := Pattern;
  Slash := 0;
  for I := 1 to Length(Pat) do
    if Pat[I] in ['/', '\'] then Slash := I;
  Pat := Copy(Pat, Slash + 1, MaxInt);
  if FSearches.Count >= 256 then raise EMKRuntime.CreateCode(4);
  L := TStringList.Create;
  All := TStringList.Create;
  try
    try
      Harness.List(All);
    except
      on E: EMKFile do begin SetDosError(3); L.Free; L := nil; Exit; end;
    end;
    for I := 0 to All.Count - 1 do
      if WildMatch(Pat, All[I]) then L.Add(All[I]);
  finally
    All.Free;
  end;
  FSearches.Add(L);
  Mem.PutInt(Sr, 4, FSearches.Count);
  Mem.PutInt(Sr + 4, 4, 0);
  FindNextFile(Sr);
end;

procedure TRun.FindNextFile(Sr: TAddr);
var
  H, Idx: Integer;
  L: TStringList;
  Name: string;
  Sz: Int64;
  MT: TDateTime;
  Short: ShortString;
begin
  H := Mem.GetInt(Sr, 4, False);
  Idx := Mem.GetInt(Sr + 4, 4, False);
  if (H = 0) or (H > FSearches.Count) then begin SetDosError(18); Exit; end;
  L := TStringList(FSearches[H - 1]);
  if L = nil then begin SetDosError(18); Exit; end;
  if Idx >= L.Count then begin SetDosError(18); Exit; end;
  Name := L[Idx];
  Mem.PutInt(Sr + 4, 4, Idx + 1);
  Sz := 0;
  MT := 0;
  try
    if Harness.HasDates then Harness.Stat(Name, Sz, MT)
    else Sz := Length(Harness.ReadFile(Name));
  except
    on E: EMKFile do ;
  end;
  Mem.PutInt(Sr + 21, 1, 32);                       // archive
  Mem.PutInt(Sr + 22, 4, PackDosTime(MT));
  Mem.PutInt(Sr + 26, 4, Sz);
  Short := Name;
  Mem.PutStr(Sr + 30, 12, Short);
  SetDosError(0);
end;

{ ---------------- Random ---------------- }

function TRun.RandomInt(N: Int64): Int64;
begin
  RandSeed := LongWord(Int64(RandSeed) * $8088405 + 1);
  if N <= 0 then Exit(0);
  Result := (Int64(RandSeed shr 16) * N) shr 16;
end;

function TRun.RandomReal: Double;
begin
  RandSeed := LongWord(Int64(RandSeed) * $8088405 + 1);
  Result := RandSeed / 4294967296.0;
end;

procedure TRun.Randomize;
begin
  RandSeed := LongWord(GetTickCount64 and $7FFFFFFF);
end;

initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := ',';
end.
