{ SPDX-License-Identifier: GPL-3.0-or-later }
unit mkp_builtins;
// Predeclared procedures and functions (System, Crt, files) as executable nodes, and the
// Write/Read statements.
{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, contnrs, Math, mkp_defs, mkp_types, mkp_mem, mkp_run, mkp_nodes;

type
  TBI = (
    // functions
    biAbs, biSqr, biSqrt, biSin, biCos, biArcTan, biLn, biExp, biInt, biFrac, biPi, biRound, biTrunc,
    biOdd, biOrd, biChr, biSucc, biPred, biLength, biCopy, biPos, biConcat, biUpCase, biLowerCase,
    biUpperCase, biRandom, biEof, biEoln, biSeekEof, biSeekEoln, biFilePos, biFileSize, biIOResult,
    biHi, biLo, biSwap, biParamCount, biParamStr, biSizeOf, biHigh, biLow, biReadKey, biKeyPressed,
    biWhereX, biWhereY, biAssigned, biMemAvail, biMaxAvail, biTypeOf, biDosVersion, biGetEnv, biFExpand, biHostCall,
    biStrLen, biStrEnd, biStrMove, biStrCopy, biStrECopy, biStrLCopy, biStrPCopy, biStrCat, biStrLCat, biStrComp,
    biStrIComp, biStrLComp, biStrLIComp, biStrScan, biStrRScan, biStrPos, biStrUpper, biStrLower, biStrPas,
    biStrNew, biAddr,
    // procedures
    biInc, biDec, biNew, biDispose, biGetMem, biFreeMem, biFillChar, biMove, biInsert, biDelete, biStr,
    biVal, biHalt, biRandomize, biInclude, biExclude, biAssign, biReset, biRewrite, biAppend, biClose,
    biErase, biRename, biFlush, biSeek, biTruncate, biBlockRead, biBlockWrite, biSetTextBuf,
    biClrScr, biClrEol, biGotoXY, biTextColor, biTextBackground, biDelay, biSound, biNoSound,
    biHighVideo, biLowVideo, biNormVideo, biExit, biBreak, biContinue, biFail, biGetDate, biGetTime,
    biFSplit, biFindFirst, biFindNext, biFindClose, biGetFTime, biSetFTime, biPackTime, biUnpackTime,
    biStrDispose, biRunError,
    biWrite, biWriteLn, biRead, biReadLn);

  TBuiltinExpr = class(TExpr)
  public
    Id: TBI;
    Args: array of TExpr;
    Soft: Boolean;           // the I-minus switch: file errors go to IOResult
    FileTyped: Boolean;
    Aux: Int64;              // TypeOf: offset of the VMT field; New function form: size of the pointed-to type
    function EvalI(C: TRun): Int64; override;
    function EvalR(C: TRun): Double; override;
    procedure EvalS(C: TRun; out S: ShortString); override;
  end;

  TBuiltinStmt = class(TStmt)
  public
    Id: TBI;
    Args: array of TExpr;
    Soft: Boolean;
    RecSize: Integer;        // Reset/Rewrite of a typed file
    Typed: Boolean;
    IsText: Boolean;         // Assign: the file variable is a Text file
    Aux: Int64;              // New/GetMem: size of the pointed-to type
    Typ0: TType;
    function Exec(C: TRun): TSig; override;
  end;

  TWriteKind = (wkInt, wkReal, wkBool, wkChar, wkStr, wkEnum, wkPChar);

  TWriteItem = class
  public
    Expr, Width, Dec: TExpr;
    Kind: TWriteKind;
    Typ: TType;
    Temp: TExpr;             // typed files: scratch variable the value is stored in before it is written
  end;

  TWriteStmt = class(TStmt)
  public
    FileE: TExpr;            // address of the file variable, nil for the console
    Items: TObjectList;
    NewLine, Soft, TypedFile: Boolean;
    constructor Create;
    destructor Destroy; override;
    function Exec(C: TRun): TSig; override;
  end;

  TReadTarget = class
  public
    Addr: TExpr;
    Typ: TType;
  end;

  TReadStmt = class(TStmt)
  public
    FileE: TExpr;
    Targets: TObjectList;
    NewLine, Soft, TypedFile: Boolean;
    constructor Create;
    destructor Destroy; override;
    function Exec(C: TRun): TSig; override;
  end;

function BuiltinByName(const Name: string; out Id: TBI): Boolean;
function IOEnter(C: TRun; Soft: Boolean): Boolean;

implementation

var
  Names: TStringList;

function BuiltinByName(const Name: string; out Id: TBI): Boolean;
var
  I: Integer;
begin
  I := Names.IndexOf(Name);
  Result := I >= 0;
  if Result then Id := TBI(PtrInt(Names.Objects[I]));
end;

// the I/O check of Turbo Pascal: a pending IOResult makes the next I/O call fail (default) or be skipped (soft)
function IOEnter(C: TRun; Soft: Boolean): Boolean;
var
  E: Integer;
begin
  Result := True;
  if C.IOResult <> 0 then
  begin
    if Soft then Exit(False);
    E := C.IOResult;
    C.IOResult := 0;
    raise EMKRuntime.CreateCode(E);
  end;
end;

function RoundHalfAway(V: Double): Int64;
begin
  if V < 0 then Result := -Trunc(-V + 0.5) else Result := Trunc(V + 0.5);
end;

function PStr(const S: ShortString): string;
begin
  Result := S;
end;

{ ---- null terminated strings (the Strings unit) ---- }

function CLen(C: TRun; A: TAddr): Integer;
begin
  Result := 0;
  while C.Mem.GetInt(A + TAddr(Result), 1, False) <> 0 do Inc(Result);
end;

function CByte(C: TRun; A: TAddr; I: Integer): Integer;
begin
  Result := Integer(C.Mem.GetInt(A + TAddr(I), 1, False));
end;

function CFold(B: Integer; IgnoreCase: Boolean): Integer;
begin
  Result := B;
  if IgnoreCase and (B >= 97) and (B <= 122) then Result := B - 32;
end;

function CCompare(C: TRun; A, B: TAddr; MaxLen: Integer; IgnoreCase: Boolean): Integer;
var
  I, X, Y: Integer;
begin
  I := 0;
  while (MaxLen < 0) or (I < MaxLen) do
  begin
    X := CFold(CByte(C, A, I), IgnoreCase);
    Y := CFold(CByte(C, B, I), IgnoreCase);
    if X <> Y then Exit(X - Y);
    if X = 0 then Exit(0);
    Inc(I);
  end;
  Result := 0;
end;

function CToString(C: TRun; A: TAddr; MaxLen: Integer): string;
var
  N, B: Integer;
begin
  Result := '';
  if A = 0 then Exit;
  N := 0;
  while N < MaxLen do
  begin
    B := CByte(C, A, N);
    if B = 0 then Break;
    Result := Result + Chr(B);
    Inc(N);
  end;
end;

function StrFunc(C: TRun; Id: TBI; const Args: array of TExpr): Int64;
var
  D, S: TAddr;
  N, M, I, J, Room: Integer;
  Ch: Integer;
  Str: ShortString;
  Found: Boolean;
begin
  Result := 0;
  case Id of
    biStrLen: Result := CLen(C, TAddr(Args[0].EvalI(C)));
    biStrEnd:
      begin
        S := TAddr(Args[0].EvalI(C));
        Result := S + TAddr(CLen(C, S));
      end;
    biStrMove:
      begin
        D := TAddr(Args[0].EvalI(C));
        S := TAddr(Args[1].EvalI(C));
        N := Integer(Args[2].EvalI(C));
        if N > 0 then C.Mem.Copy(S, D, LongWord(N));
        Result := D;
      end;
    biStrCopy, biStrECopy:
      begin
        D := TAddr(Args[0].EvalI(C));
        S := TAddr(Args[1].EvalI(C));
        N := CLen(C, S);
        C.Mem.Copy(S, D, LongWord(N + 1));
        if Id = biStrCopy then Result := D else Result := D + TAddr(N);
      end;
    biStrLCopy:
      begin
        D := TAddr(Args[0].EvalI(C));
        S := TAddr(Args[1].EvalI(C));
        M := Integer(Args[2].EvalI(C));
        N := CLen(C, S);
        if N > M then N := M;
        if N > 0 then C.Mem.Copy(S, D, LongWord(N));
        C.Mem.PutInt(D + TAddr(N), 1, 0);
        Result := D;
      end;
    biStrPCopy:
      begin
        D := TAddr(Args[0].EvalI(C));
        Args[1].EvalS(C, Str);
        N := Length(Str);
        for I := 1 to N do C.Mem.PutInt(D + TAddr(I - 1), 1, Ord(Str[I]));
        C.Mem.PutInt(D + TAddr(N), 1, 0);
        Result := D;
      end;
    biStrCat:
      begin
        D := TAddr(Args[0].EvalI(C));
        S := TAddr(Args[1].EvalI(C));
        N := CLen(C, S);
        C.Mem.Copy(S, D + TAddr(CLen(C, D)), LongWord(N + 1));
        Result := D;
      end;
    biStrLCat:
      begin
        D := TAddr(Args[0].EvalI(C));
        S := TAddr(Args[1].EvalI(C));
        M := Integer(Args[2].EvalI(C));
        I := CLen(C, D);
        Room := M - I;
        if Room > 0 then
        begin
          N := CLen(C, S);
          if N > Room then N := Room;
          if N > 0 then C.Mem.Copy(S, D + TAddr(I), LongWord(N));
          C.Mem.PutInt(D + TAddr(I + N), 1, 0);
        end;
        Result := D;
      end;
    biStrComp: Result := CCompare(C, TAddr(Args[0].EvalI(C)), TAddr(Args[1].EvalI(C)), -1, False);
    biStrIComp: Result := CCompare(C, TAddr(Args[0].EvalI(C)), TAddr(Args[1].EvalI(C)), -1, True);
    biStrLComp:
      begin
        D := TAddr(Args[0].EvalI(C));
        S := TAddr(Args[1].EvalI(C));
        Result := CCompare(C, D, S, Integer(Args[2].EvalI(C)), False);
      end;
    biStrLIComp:
      begin
        D := TAddr(Args[0].EvalI(C));
        S := TAddr(Args[1].EvalI(C));
        Result := CCompare(C, D, S, Integer(Args[2].EvalI(C)), True);
      end;
    biStrScan, biStrRScan:
      begin
        S := TAddr(Args[0].EvalI(C));
        Ch := Integer(Args[1].EvalI(C));
        N := CLen(C, S);
        if Ch = 0 then Exit(S + TAddr(N));
        Result := 0;
        for I := 0 to N - 1 do
          if CByte(C, S, I) = Ch then
          begin
            Result := S + TAddr(I);
            if Id = biStrScan then Break;
          end;
      end;
    biStrPos:
      begin
        S := TAddr(Args[0].EvalI(C));
        D := TAddr(Args[1].EvalI(C));
        N := CLen(C, S);
        M := CLen(C, D);
        Result := 0;
        if M = 0 then Exit;
        for I := 0 to N - M do
        begin
          Found := True;
          for J := 0 to M - 1 do
            if CByte(C, S, I + J) <> CByte(C, D, J) then begin Found := False; Break; end;
          if Found then Exit(S + TAddr(I));
        end;
      end;
    biStrUpper, biStrLower:
      begin
        S := TAddr(Args[0].EvalI(C));
        N := CLen(C, S);
        for I := 0 to N - 1 do
        begin
          Ch := CByte(C, S, I);
          if (Id = biStrUpper) and (Ch >= 97) and (Ch <= 122) then C.Mem.PutInt(S + TAddr(I), 1, Ch - 32)
          else if (Id = biStrLower) and (Ch >= 65) and (Ch <= 90) then C.Mem.PutInt(S + TAddr(I), 1, Ch + 32);
        end;
        Result := S;
      end;
    biStrNew:
      begin
        S := TAddr(Args[0].EvalI(C));
        if S = 0 then Exit(0);
        N := CLen(C, S);
        if N = 0 then Exit(0);
        D := C.Mem.Alloc(LongWord(N + 1));
        C.Mem.Copy(S, D, LongWord(N + 1));
        Result := D;
      end;
  end;
end;

{ ---------------- functions ---------------- }

function TBuiltinExpr.EvalI(C: TRun): Int64;
var
  S, T: ShortString;
  F: TPFile;
  A: Int64;
  X, Y: Integer;
begin
  Result := 0;
  case Id of
    biAbs: begin Result := Args[0].EvalI(C); if Result < 0 then Result := -Result; end;
    biSqr: begin Result := Args[0].EvalI(C); Result := Result * Result; end;
    biRound: Result := RoundHalfAway(Args[0].EvalR(C));
    biTrunc: Result := Trunc(Args[0].EvalR(C));
    biOdd: Result := Ord((Args[0].EvalI(C) and 1) <> 0);
    biOrd: Result := Args[0].EvalI(C);
    biChr: Result := Args[0].EvalI(C) and 255;
    biSucc: Result := Args[0].EvalI(C) + 1;
    biPred: Result := Args[0].EvalI(C) - 1;
    biLength: begin Args[0].EvalS(C, S); Result := Length(S); end;
    biPos:
      begin
        Args[0].EvalS(C, S);
        Args[1].EvalS(C, T);
        Result := Pos(S, T);
      end;
    biUpCase:
      begin
        Result := Args[0].EvalI(C);
        if (Result >= 97) and (Result <= 122) then Result := Result - 32;
      end;
    biRandom: Result := C.RandomInt(Args[0].EvalI(C));
    biEof, biEoln, biSeekEof, biSeekEoln, biFilePos, biFileSize:
      begin
        if Length(Args) > 0 then F := C.FileAt(Args[0].EvalA(C), False) else F := C.StdIn;
        if not IOEnter(C, Soft) then Exit(0);
        try
          case Id of
            biEof: Result := Ord(C.FileEof(F));
            biEoln: Result := Ord(C.FileEoln(F));
            biSeekEof: Result := Ord(C.SeekEof(F));
            biSeekEoln: Result := Ord(C.SeekEoln(F));
            biFilePos: Result := C.FilePos(F);
            biFileSize: Result := C.FileSize(F);
          end;
        except
          on E: EMKRuntime do
            if Soft and (E.Code < 200) then C.IOResult := E.Code else raise;
        end;
      end;
    biIOResult: begin Result := C.IOResult; C.IOResult := 0; end;
    biHi: Result := (Args[0].EvalI(C) shr 8) and 255;
    biLo: Result := Args[0].EvalI(C) and 255;
    biSwap:
      begin
        A := Args[0].EvalI(C);
        Result := ((A and 255) shl 8) or ((A shr 8) and 255);
      end;
    biParamCount: Result := C.Params.Count;
    biReadKey: Result := C.ReadKey;
    biKeyPressed: Result := Ord(C.KeyPressed);
    biWhereX: begin C.Term.GetXY(X, Y); Result := X; end;
    biWhereY: begin C.Term.GetXY(X, Y); Result := Y; end;
    biAssigned: Result := Ord(Args[0].EvalI(C) <> 0);
    biMemAvail, biMaxAvail: Result := C.Mem.HeapFree;
    biTypeOf: Result := C.Mem.GetInt(Args[0].EvalA(C) + TAddr(Aux), 2, False);
    biDosVersion: Result := $0007;
    biStrLen..biStrLower, biStrNew: Result := StrFunc(C, Id, Args);
    biNew:
      begin
        // New(PType, Init(...)): Args[0] = scratch pointer variable, Args[1] = the constructor call
        A := Args[0].EvalA(C);
        Result := C.Mem.Alloc(LongWord(Aux));
        C.Mem.PutInt(A, 4, Result);
        if Args[1].EvalI(C) = 0 then
        begin
          C.Mem.FreeBlock(TAddr(Result));
          Result := 0;
        end;
      end;
  else
    raise Exception.Create('internal: builtin has no integer value');
  end;
end;

function TBuiltinExpr.EvalR(C: TRun): Double;
var
  V: Double;
begin
  Result := 0;
  case Id of
    biAbs: Result := Abs(Args[0].EvalR(C));
    biSqr: begin V := Args[0].EvalR(C); Result := V * V; end;
    biSqrt:
      begin
        V := Args[0].EvalR(C);
        if V < 0 then raise EMKRuntime.CreateCode(207);
        Result := Sqrt(V);
      end;
    biSin: Result := Sin(Args[0].EvalR(C));
    biCos: Result := Cos(Args[0].EvalR(C));
    biArcTan: Result := ArcTan(Args[0].EvalR(C));
    biLn:
      begin
        V := Args[0].EvalR(C);
        if V <= 0 then raise EMKRuntime.CreateCode(207);
        Result := Ln(V);
      end;
    biExp: Result := Exp(Args[0].EvalR(C));
    biInt: Result := Trunc(Args[0].EvalR(C));
    biFrac: begin V := Args[0].EvalR(C); Result := V - Trunc(V); end;
    biPi: Result := Pi;
    biRandom: Result := C.RandomReal;
  else
    Result := EvalI(C);
  end;
end;

procedure TBuiltinExpr.EvalS(C: TRun; out S: ShortString);
var
  T, U: ShortString;
  I, N, K: Int64;
  Idx: Integer;
  HostErr: string;
  HostEx: EMKRuntime;
begin
  S := '';
  case Id of
    biCopy:
      begin
        Args[0].EvalS(C, T);
        I := Args[1].EvalI(C);
        N := Args[2].EvalI(C);
        if I < 1 then I := 1;
        if N < 0 then N := 0;
        if I > Length(T) then S := '' else S := Copy(T, Integer(I), Integer(N));
      end;
    biConcat:
      begin
        for Idx := 0 to High(Args) do
        begin
          Args[Idx].EvalS(C, T);
          if Length(S) + Length(T) > 255 then T := Copy(T, 1, 255 - Length(S));
          S := S + T;
        end;
      end;
    biLowerCase:
      begin
        Args[0].EvalS(C, T);
        S := LowerCase(T);
      end;
    biUpperCase:
      begin
        Args[0].EvalS(C, T);
        S := UpperCase(T);
      end;
    biParamStr:
      begin
        K := Args[0].EvalI(C);
        if K = 0 then U := C.ProgramName
        else if (K >= 1) and (K <= C.Params.Count) then U := C.Params[K - 1]
        else U := '';
        S := U;
      end;
    biGetEnv: S := '';
    biHostCall:
      begin
        Args[0].EvalS(C, T);
        U := C.Term.HostCall(T, HostErr);
        if HostErr <> '' then
        begin
          HostEx := EMKRuntime.CreateCode(300);
          HostEx.Message := 'Host call failed: ' + HostErr;
          raise HostEx;
        end;
        S := U;
      end;
    biStrPas: S := CToString(C, TAddr(Args[0].EvalI(C)), 255);
    biFExpand:
      begin
        Args[0].EvalS(C, T);
        S := UpperCase(T);
      end;
  else
    raise Exception.Create('internal: builtin has no string value');
  end;
end;

{ ---------------- procedures ---------------- }

function SetBase(T: TType): Integer;
begin
  Result := T.Size;
end;

function StrArg(C: TRun; E: TExpr): string;
var
  S: ShortString;
begin
  E.EvalS(C, S);
  Result := S;
end;

function ValPrefix(const S: string; IsReal: Boolean; out IntV: Int64; out RealV: Double): Integer;
// returns 0 when the whole string is a number, else the 1-based position of the first bad character
var
  I, N: Integer;
  T: string;
begin
  IntV := 0;
  RealV := 0;
  T := S;
  N := 0;
  while (N < Length(T)) and (T[N + 1] = ' ') do Inc(N);
  T := Copy(T, N + 1, MaxInt);
  if T = '' then Exit(N + 1);
  if IsReal then
  begin
    if ParseReal(T, RealV) then Exit(0);
    I := 1;
    if (T[I] in ['+', '-']) then Inc(I);
    while (I <= Length(T)) and (T[I] in ['0'..'9']) do Inc(I);
    if (I <= Length(T)) and (T[I] = '.') then begin Inc(I); while (I <= Length(T)) and (T[I] in ['0'..'9']) do Inc(I); end;
    if (I <= Length(T)) and (T[I] in ['e', 'E']) then
    begin
      Inc(I);
      if (I <= Length(T)) and (T[I] in ['+', '-']) then Inc(I);
      while (I <= Length(T)) and (T[I] in ['0'..'9']) do Inc(I);
    end;
    Exit(N + I);
  end;
  if (T[1] = '$') then
  begin
    I := 2;
    while (I <= Length(T)) and (T[I] in ['0'..'9', 'a'..'f', 'A'..'F']) do Inc(I);
    if (I > 2) and (I > Length(T)) and TryStrToInt64(T, IntV) then Exit(0);
    Exit(N + I);
  end;
  I := 1;
  if T[1] in ['+', '-'] then Inc(I);
  while (I <= Length(T)) and (T[I] in ['0'..'9']) do Inc(I);
  if (I > Length(T)) and (I > 1) and not ((I = 2) and (T[1] in ['+', '-'])) and TryStrToInt64(T, IntV) then Exit(0);
  Result := N + I;
  if Result = N + 1 then Result := N + 1;
end;

function TBuiltinStmt.Exec(C: TRun): TSig;
var
  A, B: TAddr;
  V, N, K: Int64;
  S, T: ShortString;
  F: TPFile;
  I: Integer;
  SV: TSetVal;
  RV: Double;
  Code: Integer;
  Sz: Integer;
  Signed: Boolean;
  W, D: Integer;
  YY, MM, DD, HH, MI, SS, MS: Word;
  SlashAt, DotAt: Integer;
  Ext: ShortString;
  Tm, Dt: Int64;

begin
  Result := sgNone;
  try
    case Id of
      biInc, biDec:
        begin
          A := Args[0].EvalA(C);
          if Length(Args) > 1 then N := Args[1].EvalI(C) else N := 1;
          if Id = biDec then N := -N;
          Sz := Args[0].Typ.Size;
          Signed := (Args[0].Typ.Kind = tyInt) and (Args[0].Typ.Lo < 0);
          V := C.Mem.GetInt(A, Sz, Signed);
          C.Mem.PutInt(A, Sz, V + N);
        end;
      biNew:
        begin
          A := Args[0].EvalA(C);
          B := C.Mem.Alloc(LongWord(Aux));
          C.Mem.PutInt(A, 4, B);
          if (Length(Args) > 1) and (Args[1].EvalI(C) = 0) then
          begin
            C.Mem.FreeBlock(B);                 // the constructor called Fail
            C.Mem.PutInt(A, 4, 0);
          end;
        end;
      biDispose:
        begin
          B := TAddr(Args[0].EvalI(C));
          if B = 0 then raise EMKRuntime.CreateCode(204);
          if Length(Args) > 1 then Args[1].EvalI(C);          // the destructor
          C.Mem.FreeBlock(B);
        end;
      biStrDispose:
        begin
          B := TAddr(Args[0].EvalI(C));
          if B <> 0 then C.Mem.FreeBlock(B);
        end;
      biRunError:
        begin
          if Length(Args) > 0 then N := Args[0].EvalI(C) else N := 0;
          raise EMKRuntime.CreateCode(Integer(N));
        end;
      biFail:
        begin
          C.Failed := True;
          Exit(sgExit);
        end;
      biGetDate:
        begin
          DecodeDate(C.TimeNow, YY, MM, DD);
          C.Mem.PutInt(Args[0].EvalA(C), 2, YY);
          C.Mem.PutInt(Args[1].EvalA(C), 2, MM);
          C.Mem.PutInt(Args[2].EvalA(C), 2, DD);
          C.Mem.PutInt(Args[3].EvalA(C), 2, DayOfWeek(C.TimeNow) - 1);
        end;
      biGetTime:
        begin
          DecodeTime(C.TimeNow, HH, MI, SS, MS);
          C.Mem.PutInt(Args[0].EvalA(C), 2, HH);
          C.Mem.PutInt(Args[1].EvalA(C), 2, MI);
          C.Mem.PutInt(Args[2].EvalA(C), 2, SS);
          C.Mem.PutInt(Args[3].EvalA(C), 2, MS div 10);
        end;
      biFSplit:
        begin
          Args[0].EvalS(C, S);
          SlashAt := 0;
          for I := 1 to Length(S) do
            if S[I] in ['\', '/', ':'] then SlashAt := I;
          T := Copy(S, 1, SlashAt);
          S := Copy(S, SlashAt + 1, 255);
          DotAt := 0;
          for I := 1 to Length(S) do
            if S[I] = '.' then DotAt := I;
          if DotAt > 0 then begin Ext := Copy(S, DotAt, 255); S := Copy(S, 1, DotAt - 1); end else Ext := '';
          C.Mem.PutStr(Args[1].EvalA(C), Args[1].Typ.MaxLen, T);
          C.Mem.PutStr(Args[2].EvalA(C), Args[2].Typ.MaxLen, S);
          C.Mem.PutStr(Args[3].EvalA(C), Args[3].Typ.MaxLen, Ext);
        end;
      biFindFirst:
        begin
          Args[0].EvalS(C, S);
          Args[1].EvalI(C);
          C.FindFirstFile(S, Args[2].EvalA(C));
        end;
      biFindNext: C.FindNextFile(Args[0].EvalA(C));
      biFindClose: ;
      biGetFTime:
        begin
          A := Args[0].EvalA(C);
          F := C.FileAt(A, False);
          B := Args[1].EvalA(C);
          if not IOEnter(C, Soft) then Exit;
          C.Mem.PutInt(B, 4, PackDosTime(C.GetFileTime(F)));
        end;
      biSetFTime:
        begin
          A := Args[0].EvalA(C);
          F := C.FileAt(A, False);
          V := Args[1].EvalI(C);
          if not IOEnter(C, Soft) then Exit;
          C.SetFileTime(F, UnpackDosTime(Integer(V)));
        end;
      biPackTime:
        begin
          A := Args[0].EvalA(C);
          Tm := ((C.Mem.GetInt(A + 6, 2, False) and 31) shl 11) or ((C.Mem.GetInt(A + 8, 2, False) and 63) shl 5) or
                ((C.Mem.GetInt(A + 10, 2, False) shr 1) and 31);
          Dt := (((C.Mem.GetInt(A, 2, False) - 1980) and 127) shl 9) or ((C.Mem.GetInt(A + 2, 2, False) and 15) shl 5) or
                (C.Mem.GetInt(A + 4, 2, False) and 31);
          C.Mem.PutInt(Args[1].EvalA(C), 4, LongInt(LongWord((Dt shl 16) or Tm)));
        end;
      biUnpackTime:
        begin
          V := Args[0].EvalI(C) and $FFFFFFFF;
          A := Args[1].EvalA(C);
          C.Mem.PutInt(A + 10, 2, (V and 31) * 2);
          C.Mem.PutInt(A + 8, 2, (V shr 5) and 63);
          C.Mem.PutInt(A + 6, 2, (V shr 11) and 31);
          C.Mem.PutInt(A + 4, 2, (V shr 16) and 31);
          C.Mem.PutInt(A + 2, 2, (V shr 21) and 15);
          C.Mem.PutInt(A, 2, ((V shr 25) and 127) + 1980);
        end;
      biGetMem:
        begin
          A := Args[0].EvalA(C);
          N := Args[1].EvalI(C);
          if N < 0 then N := 0;
          C.Mem.PutInt(A, 4, C.Mem.Alloc(LongWord(N)));
        end;
      biFreeMem:
        begin
          A := Args[0].EvalA(C);
          B := TAddr(C.Mem.GetInt(A, 4, False));
          if B = 0 then raise EMKRuntime.CreateCode(204);
          C.Mem.FreeBlock(B);
        end;
      biFillChar:
        begin
          A := Args[0].EvalA(C);
          N := Args[1].EvalI(C);
          V := Args[2].EvalI(C);
          if N > 0 then C.Mem.Fill(A, LongWord(N), Byte(V and 255));
        end;
      biMove:
        begin
          A := Args[0].EvalA(C);
          B := Args[1].EvalA(C);
          N := Args[2].EvalI(C);
          if N > 0 then C.Mem.Copy(A, B, LongWord(N));
        end;
      biInsert:
        begin
          Args[0].EvalS(C, S);
          A := Args[1].EvalA(C);
          N := Args[2].EvalI(C);
          C.Mem.GetStr(A, T);
          if N < 1 then N := 1;
          if N > Length(T) + 1 then N := Length(T) + 1;
          T := Copy(T, 1, Integer(N) - 1) + S + Copy(T, Integer(N), 255);
          C.Mem.PutStr(A, Args[1].Typ.MaxLen, T);
        end;
      biDelete:
        begin
          A := Args[0].EvalA(C);
          N := Args[1].EvalI(C);
          K := Args[2].EvalI(C);
          C.Mem.GetStr(A, T);
          if (N >= 1) and (K >= 0) and (N <= Length(T)) then
          begin
            Delete(T, Integer(N), Integer(K));
            C.Mem.PutStr(A, Args[0].Typ.MaxLen, T);
          end;
        end;
      biStr:
        begin
          // Args: value, width (or nil), decimals (or nil), destination string
          W := NoWidth;
          D := -1;
          if Args[1] <> nil then W := Args[1].EvalI(C);
          if Args[2] <> nil then D := Args[2].EvalI(C);
          if Args[0].Cls = ecReal then
          begin
            if Args[1] = nil then T := FmtReal(Args[0].EvalR(C), NoWidth, -1)
            else T := FmtReal(Args[0].EvalR(C), W, D);
          end
          else
            T := FmtInt(Args[0].EvalI(C), W);
          A := Args[3].EvalA(C);
          C.Mem.PutStr(A, Args[3].Typ.MaxLen, T);
        end;
      biVal:
        begin
          Args[0].EvalS(C, S);
          A := Args[1].EvalA(C);
          B := Args[2].EvalA(C);
          if Args[1].Cls = ecReal then
          begin
            Code := ValPrefix(S, True, N, RV);
            if Code = 0 then C.Mem.PutReal(A, Args[1].Typ.RealKind, RV)
            else C.Mem.PutReal(A, Args[1].Typ.RealKind, 0);
          end
          else
          begin
            Code := ValPrefix(S, False, N, RV);
            if Code = 0 then C.Mem.PutInt(A, Args[1].Typ.Size, N)
            else C.Mem.PutInt(A, Args[1].Typ.Size, 0);
          end;
          C.Mem.PutInt(B, Args[2].Typ.Size, Code);
        end;
      biHalt:
        begin
          if Length(Args) > 0 then N := Args[0].EvalI(C) else N := 0;
          raise EMKHalt.CreateCode(Integer(N));
        end;
      biRandomize: C.Randomize;
      biInclude, biExclude:
        begin
          A := Args[0].EvalA(C);
          V := Args[1].EvalI(C);
          Sz := Args[0].Typ.Size;
          if (V >= 0) and ((V shr 3) < Sz) then
          begin
            I := C.Mem.GetInt(A + TAddr(V shr 3), 1, False);
            if Id = biInclude then I := I or (1 shl (V and 7)) else I := I and not (1 shl (V and 7));
            C.Mem.PutInt(A + TAddr(V shr 3), 1, I);
          end;
        end;
      biAssign:
        begin
          A := Args[0].EvalA(C);
          C.AssignFile(A, StrArg(C, Args[1]), IsText);
        end;
      biReset, biRewrite, biAppend, biClose, biErase, biRename, biFlush, biSeek, biTruncate:
        begin
          A := Args[0].EvalA(C);
          F := C.FileAt(A, False);
          N := 128;
          if Typed then N := RecSize
          else if (Length(Args) > 1) and (Id in [biReset, biRewrite]) then N := Args[1].EvalI(C);
          if (Id = biSeek) then N := Args[1].EvalI(C);
          if Id = biRename then S := '' ;
          if Id = biRename then T := ShortString(StrArg(C, Args[1]));
          if not IOEnter(C, Soft) then Exit;
          case Id of
            biReset: C.ResetFile(F, Integer(N), Typed);
            biRewrite: C.RewriteFile(F, Integer(N), Typed);
            biAppend: C.AppendFile(F);
            biClose: C.CloseFile(F, False);
            biErase: C.EraseFile(F);
            biRename: C.RenameFile(F, T);
            biFlush: begin C.NeedOpen(F); C.FlushFile(F); end;
            biSeek: C.SeekRec(F, N);
            biTruncate: C.TruncateFile(F);
          end;
        end;
      biBlockRead, biBlockWrite:
        begin
          A := Args[0].EvalA(C);
          B := Args[1].EvalA(C);
          N := Args[2].EvalI(C);
          F := C.FileAt(A, False);
          if not IOEnter(C, Soft) then Exit;
          if Id = biBlockRead then K := C.BlockRead(F, B, Integer(N)) else K := C.BlockWrite(F, B, Integer(N));
          if Length(Args) > 3 then
            C.Mem.PutInt(Args[3].EvalA(C), Args[3].Typ.Size, K)
          else if K < N then
            raise EMKRuntime.CreateCode(100 + Ord(Id = biBlockWrite));
        end;
      biSetTextBuf: ;
      biClrScr: C.Term.ClearScreen;
      biClrEol: C.Out(#27'[K');
      biGotoXY: C.Term.GotoXY(Integer(Args[0].EvalI(C)), Integer(Args[1].EvalI(C)));
      biTextColor: begin C.Crt_Fg := Integer(Args[0].EvalI(C)) and 15; C.Term.SetColor(C.Crt_Fg, C.Crt_Bg); end;
      biTextBackground: begin C.Crt_Bg := Integer(Args[0].EvalI(C)) and 7; C.Term.SetColor(C.Crt_Fg, C.Crt_Bg); end;
      biHighVideo: begin C.Crt_Fg := C.Crt_Fg or 8; C.Term.SetColor(C.Crt_Fg, C.Crt_Bg); end;
      biLowVideo: begin C.Crt_Fg := C.Crt_Fg and 7; C.Term.SetColor(C.Crt_Fg, C.Crt_Bg); end;
      biNormVideo: begin C.Crt_Fg := 7; C.Crt_Bg := 0; C.Term.SetColor(7, 0); end;
      biDelay: C.Delay(Integer(Args[0].EvalI(C)));
      biSound, biNoSound: ;
    else
      raise Exception.Create('internal: builtin procedure not implemented');
    end;
  except
    on E: EMKRuntime do
      if Soft and (E.Code < 200) then C.IOResult := E.Code else raise;
  end;
end;

{ ---------------- Write / WriteLn ---------------- }

constructor TWriteStmt.Create;
begin
  inherited Create;
  Items := TObjectList.Create(True);
end;

destructor TWriteStmt.Destroy;
begin
  Items.Free;
  inherited Destroy;
end;

function FormatItem(C: TRun; It: TWriteItem): string;
var
  W, D: Integer;
  S: ShortString;
  V: Int64;
begin
  W := NoWidth;
  D := -1;
  if It.Width <> nil then W := Integer(It.Width.EvalI(C));
  if It.Dec <> nil then D := Integer(It.Dec.EvalI(C));
  case It.Kind of
    wkInt: Result := FmtInt(It.Expr.EvalI(C), W);
    wkReal: Result := FmtReal(It.Expr.EvalR(C), W, D);
    wkBool: if It.Expr.EvalI(C) <> 0 then Result := FmtPad('TRUE', W) else Result := FmtPad('FALSE', W);
    wkChar: Result := FmtPad(Chr(Byte(It.Expr.EvalI(C))), W);
    wkStr: begin It.Expr.EvalS(C, S); Result := FmtPad(S, W); end;
    wkPChar: Result := FmtPad(CToString(C, TAddr(It.Expr.EvalI(C)), 65535), W);
    wkEnum:
      begin
        V := It.Expr.EvalI(C);
        if (V >= 0) and (V < It.Typ.EnumNames.Count) then Result := FmtPad(It.Typ.EnumNames[Integer(V)], W)
        else Result := FmtPad(IntToStr(V), W);
      end;
  end;
end;

function TWriteStmt.Exec(C: TRun): TSig;
var
  Text: string;
  I: Integer;
  It: TWriteItem;
  F: TPFile;
  A: TAddr;
begin
  Result := sgNone;
  try
    if FileE <> nil then F := C.FileAt(FileE.EvalA(C), False) else F := C.StdOut;
    if TypedFile then
    begin
      { evaluate every value first, then the I/O check, then write }
      for I := 0 to Items.Count - 1 do
      begin
        It := TWriteItem(Items[I]);
        StoreValue(C, It.Expr, It.Temp.EvalA(C), It.Typ);
      end;
      if not IOEnter(C, Soft) then Exit;
      for I := 0 to Items.Count - 1 do
      begin
        A := TWriteItem(Items[I]).Temp.EvalA(C);
        C.WriteRecord(F, A);
      end;
      Exit;
    end;
    Text := '';
    for I := 0 to Items.Count - 1 do Text := Text + FormatItem(C, TWriteItem(Items[I]));
    if NewLine then Text := Text + #13#10;
    if not IOEnter(C, Soft) then Exit;
    C.WriteText(F, Text);
  except
    on E: EMKRuntime do
      if Soft and (E.Code < 200) then C.IOResult := E.Code else raise;
  end;
end;

{ ---------------- Read / ReadLn ---------------- }

constructor TReadStmt.Create;
begin
  inherited Create;
  Targets := TObjectList.Create(True);
end;

destructor TReadStmt.Destroy;
begin
  Targets.Free;
  inherited Destroy;
end;

function TReadStmt.Exec(C: TRun): TSig;
var
  I: Integer;
  T: TReadTarget;
  F: TPFile;
  A: TAddr;
  S: ShortString;
begin
  Result := sgNone;
  try
    if FileE <> nil then F := C.FileAt(FileE.EvalA(C), False) else F := C.StdIn;
    if not IOEnter(C, Soft) then Exit;
    for I := 0 to Targets.Count - 1 do
    begin
      T := TReadTarget(Targets[I]);
      A := T.Addr.EvalA(C);
      if TypedFile then
        C.ReadRecord(F, A)
      else
        case T.Typ.Kind of
          tyChar: C.Mem.PutInt(A, 1, C.TextChar(F));
          tyInt: C.Mem.PutInt(A, T.Typ.Size, C.TextInt(F));
          tyReal: C.Mem.PutReal(A, T.Typ.RealKind, C.TextReal(F));
          tyString:
            begin
              S := C.TextStr(F, T.Typ.MaxLen);
              C.Mem.PutStr(A, T.Typ.MaxLen, S);
            end;
        end;
    end;
    if NewLine then C.TextLnEnd(F);
  except
    on E: EMKRuntime do
      if Soft and (E.Code < 200) then C.IOResult := E.Code else raise;
  end;
end;

initialization
  Names := TStringList.Create;
  Names.CaseSensitive := False;
  Names.Sorted := True;
  Names.Duplicates := dupIgnore;
  Names.AddObject('Abs', TObject(PtrInt(biAbs)));
  Names.AddObject('Sqr', TObject(PtrInt(biSqr)));
  Names.AddObject('Sqrt', TObject(PtrInt(biSqrt)));
  Names.AddObject('Sin', TObject(PtrInt(biSin)));
  Names.AddObject('Cos', TObject(PtrInt(biCos)));
  Names.AddObject('ArcTan', TObject(PtrInt(biArcTan)));
  Names.AddObject('Ln', TObject(PtrInt(biLn)));
  Names.AddObject('Exp', TObject(PtrInt(biExp)));
  Names.AddObject('Int', TObject(PtrInt(biInt)));
  Names.AddObject('Frac', TObject(PtrInt(biFrac)));
  Names.AddObject('Pi', TObject(PtrInt(biPi)));
  Names.AddObject('Round', TObject(PtrInt(biRound)));
  Names.AddObject('Trunc', TObject(PtrInt(biTrunc)));
  Names.AddObject('Odd', TObject(PtrInt(biOdd)));
  Names.AddObject('Ord', TObject(PtrInt(biOrd)));
  Names.AddObject('Chr', TObject(PtrInt(biChr)));
  Names.AddObject('Succ', TObject(PtrInt(biSucc)));
  Names.AddObject('Pred', TObject(PtrInt(biPred)));
  Names.AddObject('Length', TObject(PtrInt(biLength)));
  Names.AddObject('Copy', TObject(PtrInt(biCopy)));
  Names.AddObject('Pos', TObject(PtrInt(biPos)));
  Names.AddObject('Concat', TObject(PtrInt(biConcat)));
  Names.AddObject('UpCase', TObject(PtrInt(biUpCase)));
  Names.AddObject('LowerCase', TObject(PtrInt(biLowerCase)));
  Names.AddObject('UpperCase', TObject(PtrInt(biUpperCase)));
  Names.AddObject('Random', TObject(PtrInt(biRandom)));
  Names.AddObject('Eof', TObject(PtrInt(biEof)));
  Names.AddObject('Eoln', TObject(PtrInt(biEoln)));
  Names.AddObject('SeekEof', TObject(PtrInt(biSeekEof)));
  Names.AddObject('SeekEoln', TObject(PtrInt(biSeekEoln)));
  Names.AddObject('FilePos', TObject(PtrInt(biFilePos)));
  Names.AddObject('FileSize', TObject(PtrInt(biFileSize)));
  Names.AddObject('IOResult', TObject(PtrInt(biIOResult)));
  Names.AddObject('Hi', TObject(PtrInt(biHi)));
  Names.AddObject('Lo', TObject(PtrInt(biLo)));
  Names.AddObject('Swap', TObject(PtrInt(biSwap)));
  Names.AddObject('ParamCount', TObject(PtrInt(biParamCount)));
  Names.AddObject('ParamStr', TObject(PtrInt(biParamStr)));
  Names.AddObject('SizeOf', TObject(PtrInt(biSizeOf)));
  Names.AddObject('High', TObject(PtrInt(biHigh)));
  Names.AddObject('Low', TObject(PtrInt(biLow)));
  Names.AddObject('ReadKey', TObject(PtrInt(biReadKey)));
  Names.AddObject('KeyPressed', TObject(PtrInt(biKeyPressed)));
  Names.AddObject('WhereX', TObject(PtrInt(biWhereX)));
  Names.AddObject('WhereY', TObject(PtrInt(biWhereY)));
  Names.AddObject('Assigned', TObject(PtrInt(biAssigned)));
  Names.AddObject('MemAvail', TObject(PtrInt(biMemAvail)));
  Names.AddObject('MaxAvail', TObject(PtrInt(biMaxAvail)));
  Names.AddObject('Addr', TObject(PtrInt(biAddr)));
  Names.AddObject('Inc', TObject(PtrInt(biInc)));
  Names.AddObject('Dec', TObject(PtrInt(biDec)));
  Names.AddObject('New', TObject(PtrInt(biNew)));
  Names.AddObject('Dispose', TObject(PtrInt(biDispose)));
  Names.AddObject('GetMem', TObject(PtrInt(biGetMem)));
  Names.AddObject('FreeMem', TObject(PtrInt(biFreeMem)));
  Names.AddObject('FillChar', TObject(PtrInt(biFillChar)));
  Names.AddObject('Move', TObject(PtrInt(biMove)));
  Names.AddObject('Insert', TObject(PtrInt(biInsert)));
  Names.AddObject('Delete', TObject(PtrInt(biDelete)));
  Names.AddObject('Str', TObject(PtrInt(biStr)));
  Names.AddObject('Val', TObject(PtrInt(biVal)));
  Names.AddObject('Halt', TObject(PtrInt(biHalt)));
  Names.AddObject('Randomize', TObject(PtrInt(biRandomize)));
  Names.AddObject('Include', TObject(PtrInt(biInclude)));
  Names.AddObject('Exclude', TObject(PtrInt(biExclude)));
  Names.AddObject('Assign', TObject(PtrInt(biAssign)));
  Names.AddObject('Reset', TObject(PtrInt(biReset)));
  Names.AddObject('Rewrite', TObject(PtrInt(biRewrite)));
  Names.AddObject('Append', TObject(PtrInt(biAppend)));
  Names.AddObject('Close', TObject(PtrInt(biClose)));
  Names.AddObject('Erase', TObject(PtrInt(biErase)));
  Names.AddObject('Rename', TObject(PtrInt(biRename)));
  Names.AddObject('Flush', TObject(PtrInt(biFlush)));
  Names.AddObject('Seek', TObject(PtrInt(biSeek)));
  Names.AddObject('Truncate', TObject(PtrInt(biTruncate)));
  Names.AddObject('BlockRead', TObject(PtrInt(biBlockRead)));
  Names.AddObject('BlockWrite', TObject(PtrInt(biBlockWrite)));
  Names.AddObject('SetTextBuf', TObject(PtrInt(biSetTextBuf)));
  Names.AddObject('ClrScr', TObject(PtrInt(biClrScr)));
  Names.AddObject('ClrEol', TObject(PtrInt(biClrEol)));
  Names.AddObject('GotoXY', TObject(PtrInt(biGotoXY)));
  Names.AddObject('TextColor', TObject(PtrInt(biTextColor)));
  Names.AddObject('TextBackground', TObject(PtrInt(biTextBackground)));
  Names.AddObject('Delay', TObject(PtrInt(biDelay)));
  Names.AddObject('Sound', TObject(PtrInt(biSound)));
  Names.AddObject('NoSound', TObject(PtrInt(biNoSound)));
  Names.AddObject('HighVideo', TObject(PtrInt(biHighVideo)));
  Names.AddObject('LowVideo', TObject(PtrInt(biLowVideo)));
  Names.AddObject('NormVideo', TObject(PtrInt(biNormVideo)));
  Names.AddObject('Exit', TObject(PtrInt(biExit)));
  Names.AddObject('Break', TObject(PtrInt(biBreak)));
  Names.AddObject('Continue', TObject(PtrInt(biContinue)));
  Names.AddObject('TypeOf', TObject(PtrInt(biTypeOf)));
  Names.AddObject('DosVersion', TObject(PtrInt(biDosVersion)));
  Names.AddObject('GetEnv', TObject(PtrInt(biGetEnv)));
  Names.AddObject('HostCall', TObject(PtrInt(biHostCall)));
  Names.AddObject('FExpand', TObject(PtrInt(biFExpand)));
  Names.AddObject('Fail', TObject(PtrInt(biFail)));
  Names.AddObject('GetDate', TObject(PtrInt(biGetDate)));
  Names.AddObject('GetTime', TObject(PtrInt(biGetTime)));
  Names.AddObject('FSplit', TObject(PtrInt(biFSplit)));
  Names.AddObject('FindFirst', TObject(PtrInt(biFindFirst)));
  Names.AddObject('FindNext', TObject(PtrInt(biFindNext)));
  Names.AddObject('FindClose', TObject(PtrInt(biFindClose)));
  Names.AddObject('GetFTime', TObject(PtrInt(biGetFTime)));
  Names.AddObject('SetFTime', TObject(PtrInt(biSetFTime)));
  Names.AddObject('PackTime', TObject(PtrInt(biPackTime)));
  Names.AddObject('UnpackTime', TObject(PtrInt(biUnpackTime)));
  Names.AddObject('StrLen', TObject(PtrInt(biStrLen)));
  Names.AddObject('StrEnd', TObject(PtrInt(biStrEnd)));
  Names.AddObject('StrMove', TObject(PtrInt(biStrMove)));
  Names.AddObject('StrCopy', TObject(PtrInt(biStrCopy)));
  Names.AddObject('StrECopy', TObject(PtrInt(biStrECopy)));
  Names.AddObject('StrLCopy', TObject(PtrInt(biStrLCopy)));
  Names.AddObject('StrPCopy', TObject(PtrInt(biStrPCopy)));
  Names.AddObject('StrCat', TObject(PtrInt(biStrCat)));
  Names.AddObject('StrLCat', TObject(PtrInt(biStrLCat)));
  Names.AddObject('StrComp', TObject(PtrInt(biStrComp)));
  Names.AddObject('StrIComp', TObject(PtrInt(biStrIComp)));
  Names.AddObject('StrLComp', TObject(PtrInt(biStrLComp)));
  Names.AddObject('StrLIComp', TObject(PtrInt(biStrLIComp)));
  Names.AddObject('StrScan', TObject(PtrInt(biStrScan)));
  Names.AddObject('StrRScan', TObject(PtrInt(biStrRScan)));
  Names.AddObject('StrPos', TObject(PtrInt(biStrPos)));
  Names.AddObject('StrUpper', TObject(PtrInt(biStrUpper)));
  Names.AddObject('StrLower', TObject(PtrInt(biStrLower)));
  Names.AddObject('StrPas', TObject(PtrInt(biStrPas)));
  Names.AddObject('StrNew', TObject(PtrInt(biStrNew)));
  Names.AddObject('StrDispose', TObject(PtrInt(biStrDispose)));
  Names.AddObject('RunError', TObject(PtrInt(biRunError)));
  Names.AddObject('Write', TObject(PtrInt(biWrite)));
  Names.AddObject('WriteLn', TObject(PtrInt(biWriteLn)));
  Names.AddObject('Read', TObject(PtrInt(biRead)));
  Names.AddObject('ReadLn', TObject(PtrInt(biReadLn)));
finalization
  Names.Free;
end.
