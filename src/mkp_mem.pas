unit mkp_mem;
// The byte addressed memory every Pascal variable lives in: global variables, the stack and the heap.
// Records, arrays, strings (length byte + characters) and sets have their Turbo Pascal layout, so
// Move, FillChar, BlockRead, variable typecasts and untyped parameters work on real bytes.
{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, mkp_defs, mkp_types;

type
  TAddr = LongWord;
  PMemByte = ^Byte;

  TMem = class
  private
    FSize: LongWord;
  public
    Data: PByte;
    HeapBase, HeapTop: TAddr;       // heap region [HeapBase, HeapTop)
    HeapEnd: TAddr;                 // end of blocks handed out so far
    StackBase: TAddr;               // lowest address the stack may reach
    constructor Create(ASize: LongWord);
    destructor Destroy; override;
    property Size: LongWord read FSize;
    { checked pointer to N bytes at A (runtime error 204 when A is nil or outside memory) }
    function P(A: TAddr; N: LongWord): PByte; inline;
    function GetInt(A: TAddr; Sz: Integer; Signed: Boolean): Int64;
    procedure PutInt(A: TAddr; Sz: Integer; V: Int64);
    function GetReal(A: TAddr; K: TRealKind): Double;
    procedure PutReal(A: TAddr; K: TRealKind; V: Double);
    procedure GetStr(A: TAddr; out S: ShortString);
    procedure PutStr(A: TAddr; MaxLen: Integer; const S: ShortString);
    procedure Fill(A: TAddr; N: LongWord; V: Byte);
    procedure Copy(Src, Dst: TAddr; N: LongWord);
    { heap }
    procedure InitHeap(AHeapBase, AHeapTop: TAddr);
    function Alloc(N: LongWord): TAddr;           // zero filled; runtime error 203 when full
    procedure FreeBlock(A: TAddr);
    function HeapFree: LongWord;
  end;

function Real6ToDouble(P: PByte): Double;
procedure DoubleToReal6(V: Double; P: PByte);

implementation

constructor TMem.Create(ASize: LongWord);
begin
  inherited Create;
  FSize := ASize;
  GetMem(Data, ASize);
  FillChar(Data^, 64, 0);
end;

destructor TMem.Destroy;
begin
  FreeMem(Data);
  inherited Destroy;
end;

function TMem.P(A: TAddr; N: LongWord): PByte;
begin
  if (A < 16) or (QWord(A) + N > FSize) then raise EMKRuntime.CreateCode(204);
  Result := Data + A;
end;

{ ---------------- 6 byte Real ---------------- }

function Real6ToDouble(P: PByte): Double;
var
  E: Integer;
  Lo: LongWord;
  Hi: Byte;
  Frac: Double;
begin
  E := P[0];
  if E = 0 then Exit(0.0);
  Lo := PLongWord(P + 1)^;
  Hi := P[5] and $7F;
  Frac := Lo + Hi * 4294967296.0;
  Result := (1.0 + Frac / 549755813888.0) * Ldexp(1.0, E - 129);
  if (P[5] and $80) <> 0 then Result := -Result;
end;

procedure DoubleToReal6(V: Double; P: PByte);
var
  A, M: Double;
  E: Integer;
  Frac: Double;
  Lo: LongWord;
  Hi: Int64;
  Sign: Byte;
begin
  FillChar(P^, 6, 0);
  if (V = 0) or IsNan(V) or IsInfinite(V) then Exit;
  Sign := 0;
  A := V;
  if A < 0 then begin Sign := 1; A := -A; end;
  E := Floor(Ln(A) / Ln(2));
  M := Ldexp(A, -E);
  if M >= 2 then begin M := M / 2; Inc(E); end;
  if M < 1 then begin M := M * 2; Dec(E); end;
  Frac := Round((M - 1) * 549755813888.0);
  if Frac >= 549755813888.0 then begin Frac := 0; Inc(E); end;
  E := E + 129;
  if E < 1 then Exit;
  if E > 255 then begin E := 255; Frac := 549755813887.0; end;
  P[0] := E;
  Hi := Trunc(Frac / 4294967296.0);
  Lo := Trunc(Frac - Hi * 4294967296.0);
  PLongWord(P + 1)^ := Lo;
  P[5] := (Hi and $7F) or (Sign shl 7);
end;

{ ---------------- typed access ---------------- }

function TMem.GetInt(A: TAddr; Sz: Integer; Signed: Boolean): Int64;
var
  Q: PByte;
begin
  Q := P(A, Sz);
  case Sz of
    1: if Signed then Result := ShortInt(Q^) else Result := Q^;
    2: if Signed then Result := SmallInt(PWord(Q)^) else Result := PWord(Q)^;
    4: if Signed then Result := LongInt(PLongWord(Q)^) else Result := PLongWord(Q)^;
    8: Result := PInt64(Q)^;
  else
    Result := 0;
  end;
end;

procedure TMem.PutInt(A: TAddr; Sz: Integer; V: Int64);
var
  Q: PByte;
begin
  Q := P(A, Sz);
  case Sz of
    1: Q^ := Byte(V and $FF);
    2: PWord(Q)^ := Word(V and $FFFF);
    4: PLongWord(Q)^ := LongWord(V and $FFFFFFFF);
    8: PInt64(Q)^ := V;
  end;
end;

function TMem.GetReal(A: TAddr; K: TRealKind): Double;
var
  Q: PByte;
  E: Extended;
begin
  case K of
    rkReal6: begin Q := P(A, 6); Result := Real6ToDouble(Q); end;
    rkSingle: begin Q := P(A, 4); Result := PSingle(Q)^; end;
    rkDouble: begin Q := P(A, 8); Result := PDouble(Q)^; end;
    rkExtended:
      begin
        Q := P(A, 10);
        E := 0;
        Move(Q^, E, 10);
        Result := E;
      end;
    rkComp: begin Q := P(A, 8); Result := PInt64(Q)^; end;
  else
    Result := 0;
  end;
end;

procedure TMem.PutReal(A: TAddr; K: TRealKind; V: Double);
var
  Q: PByte;
  E: Extended;
begin
  case K of
    rkReal6: begin Q := P(A, 6); DoubleToReal6(V, Q); end;
    rkSingle: begin Q := P(A, 4); PSingle(Q)^ := V; end;
    rkDouble: begin Q := P(A, 8); PDouble(Q)^ := V; end;
    rkExtended:
      begin
        Q := P(A, 10);
        E := V;
        Move(E, Q^, 10);
      end;
    rkComp: begin Q := P(A, 8); PInt64(Q)^ := Round(V); end;
  end;
end;

procedure TMem.GetStr(A: TAddr; out S: ShortString);
var
  Q: PByte;
  N: Integer;
begin
  Q := P(A, 1);
  N := Q^;
  Q := P(A, N + 1);
  S[0] := Chr(N);
  if N > 0 then System.Move((Q + 1)^, S[1], N);
end;

procedure TMem.PutStr(A: TAddr; MaxLen: Integer; const S: ShortString);
var
  Q: PByte;
  N: Integer;
begin
  N := Length(S);
  if N > MaxLen then N := MaxLen;
  Q := P(A, N + 1);
  Q^ := N;
  if N > 0 then System.Move(S[1], (Q + 1)^, N);
end;

procedure TMem.Fill(A: TAddr; N: LongWord; V: Byte);
begin
  if N = 0 then Exit;
  FillChar(P(A, N)^, N, V);
end;

procedure TMem.Copy(Src, Dst: TAddr; N: LongWord);
begin
  if N = 0 then Exit;
  System.Move(P(Src, N)^, P(Dst, N)^, N);
end;

{ ---------------- heap: blocks with an 8 byte header (size, in-use flag) ---------------- }

procedure TMem.InitHeap(AHeapBase, AHeapTop: TAddr);
begin
  HeapBase := (AHeapBase + 7) and not TAddr(7);
  HeapTop := AHeapTop;
  HeapEnd := HeapBase;
end;

function TMem.Alloc(N: LongWord): TAddr;
var
  A: TAddr;
  Sz, Have: LongWord;
begin
  Sz := (N + 7) and not LongWord(7);
  if Sz = 0 then Sz := 8;
  { first fit through the blocks handed out so far }
  A := HeapBase;
  while A < HeapEnd do
  begin
    Have := PLongWord(Data + A)^;
    if (PLongWord(Data + A + 4)^ = 0) and (Have >= Sz) then
    begin
      if Have >= Sz + 16 then
      begin                                         // split
        PLongWord(Data + A + 8 + Sz)^ := Have - Sz - 8;
        PLongWord(Data + A + 8 + Sz + 4)^ := 0;
        PLongWord(Data + A)^ := Sz;
        Have := Sz;
      end;
      PLongWord(Data + A + 4)^ := 1;
      FillChar((Data + A + 8)^, Have, 0);
      Exit(A + 8);
    end;
    A := A + 8 + Have;
  end;
  if QWord(HeapEnd) + 8 + Sz > HeapTop then raise EMKRuntime.CreateCode(203);
  PLongWord(Data + HeapEnd)^ := Sz;
  PLongWord(Data + HeapEnd + 4)^ := 1;
  FillChar((Data + HeapEnd + 8)^, Sz, 0);
  Result := HeapEnd + 8;
  HeapEnd := HeapEnd + 8 + Sz;
end;

procedure TMem.FreeBlock(A: TAddr);
var
  H, Nx: TAddr;
begin
  if (A < HeapBase + 8) or (A >= HeapEnd) then raise EMKRuntime.CreateCode(204);
  H := A - 8;
  if PLongWord(Data + H + 4)^ <> 1 then raise EMKRuntime.CreateCode(204);
  PLongWord(Data + H + 4)^ := 0;
  { merge with following free blocks }
  Nx := H + 8 + PLongWord(Data + H)^;
  while (Nx < HeapEnd) and (PLongWord(Data + Nx + 4)^ = 0) do
  begin
    PLongWord(Data + H)^ := PLongWord(Data + H)^ + 8 + PLongWord(Data + Nx)^;
    Nx := H + 8 + PLongWord(Data + H)^;
  end;
  if Nx >= HeapEnd then HeapEnd := H;               // the last block went free: give it back
end;

function TMem.HeapFree: LongWord;
begin
  Result := HeapTop - HeapEnd;
end;

end.
