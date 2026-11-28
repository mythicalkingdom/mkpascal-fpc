{ SPDX-License-Identifier: GPL-3.0-or-later }
unit mkp_nodes;
// The executable tree the compiler builds.  Expressions know their type; ordinals, pointers and
// procedures evaluate to Int64, reals to Double, strings to ShortString, sets to a 32 byte bitmap, and
// records/arrays/objects to the address of their bytes.
{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, contnrs, Math, mkp_defs, mkp_types, mkp_mem, mkp_run;

threadvar
  NodePool: TObjectList;      // while compiling: owns every node that is created

type
  TSig = (sgNone, sgBreak, sgContinue, sgExit, sgGoto);
  TSetVal = array[0..31] of Byte;
  TWrap = (wNone, wI16, wU16, wI32);
  TArithOp = (aoAdd, aoSub, aoMul, aoDiv, aoMod, aoAnd, aoOr, aoXor, aoShl, aoShr);
  TCmp = (cEq, cNe, cLt, cGt, cLe, cGe);

  TStmt = class;

  TRoutine = class
  public
    Name: string;
    Params: TObjectList;       // TParamDesc (owned)
    Ret: TType;                // nil for a procedure
    ResultOffset: Integer;
    FrameSize: Integer;
    Body: TStmt;
    Level: Integer;            // 1 for routines declared in the program
    Forward: Boolean;
    Defined: Boolean;
    DeclLine: Integer;
    Owner: TType;              // methods: the object type
    IsVirtual, IsCtor, IsDtor: Boolean;
    VIndex: Integer;           // virtual methods: slot in the VMT
    Intf: Boolean;             // declared in a unit's interface
    ProcId: Integer;           // procedural value of the routine (0 = its address was never taken)
    ProcType: TType;
    constructor Create;
    destructor Destroy; override;
  end;

  { ---------------- expressions ---------------- }

  TExpr = class
  public
    Typ: TType;
    Line: Integer;
    constructor Create;
    function EvalI(C: TRun): Int64; virtual;
    function EvalR(C: TRun): Double; virtual;
    procedure EvalS(C: TRun; out S: ShortString); virtual;
    procedure EvalSet(C: TRun; var S: TSetVal); virtual;
    function EvalA(C: TRun): TAddr; virtual;
    function IsConst: Boolean; virtual;
    function IsLValue: Boolean; virtual;
    function Cls: TExprClass;
  end;

  TConstInt = class(TExpr)
  public
    Value: Int64;
    constructor Create(AValue: Int64; AType: TType);
    function EvalI(C: TRun): Int64; override;
    function IsConst: Boolean; override;
  end;

  TConstReal = class(TExpr)
  public
    Value: Double;
    constructor Create(AValue: Double; AType: TType);
    function EvalR(C: TRun): Double; override;
    function IsConst: Boolean; override;
  end;

  TConstStr = class(TExpr)
  public
    Value: ShortString;
    constructor Create(const AValue: ShortString; AType: TType);
    procedure EvalS(C: TRun; out S: ShortString); override;
    function IsConst: Boolean; override;
  end;

  TConstSet = class(TExpr)
  public
    Value: TSetVal;
    constructor Create(const AValue: TSetVal; AType: TType);
    procedure EvalSet(C: TRun; var S: TSetVal); override;
    function IsConst: Boolean; override;
  end;

  { names a type where an expression is expected (SizeOf(Integer), High(TArr), type casts) }
  TTypeRef = class(TExpr)
  end;

  { ---- addresses (variables) ---- }
  TAddrExpr = class(TExpr)
  public
    function IsLValue: Boolean; override;
  end;

  TGlobalAddr = class(TAddrExpr)
  public
    Addr: TAddr;
    constructor Create(AAddr: TAddr; AType: TType);
    function EvalA(C: TRun): TAddr; override;
  end;

  TLocalAddr = class(TAddrExpr)
  public
    Offset, Hops: Integer;
    constructor Create(AOffset, AHops: Integer; AType: TType);
    function EvalA(C: TRun): TAddr; override;
  end;

  { a var parameter: the frame slot holds the address of the caller's variable }
  TVarParamAddr = class(TAddrExpr)
  public
    Offset, Hops: Integer;
    constructor Create(AOffset, AHops: Integer; AType: TType);
    function EvalA(C: TRun): TAddr; override;
  end;

  TDerefAddr = class(TAddrExpr)
  public
    Ptr: TExpr;
    constructor Create(APtr: TExpr; AType: TType);
    function EvalA(C: TRun): TAddr; override;
  end;

  TFieldAddr = class(TAddrExpr)
  public
    Base: TExpr;
    Offset: Integer;
    constructor Create(ABase: TExpr; AOffset: Integer; AType: TType);
    function EvalA(C: TRun): TAddr; override;
  end;

  TIndexAddr = class(TAddrExpr)
  public
    Base, Index: TExpr;
    Lo, Hi: Int64;
    ElemSize: Integer;
    constructor Create(ABase, AIndex: TExpr; ALo, AHi: Int64; AElemSize: Integer; AType: TType);
    function EvalA(C: TRun): TAddr; override;
  end;

  { s[i] of a string variable: i = 0 is the length byte }
  TStrElemAddr = class(TAddrExpr)
  public
    Base, Index: TExpr;
    MaxLen: Integer;
    constructor Create(ABase, AIndex: TExpr; AMaxLen: Integer; AType: TType);
    function EvalA(C: TRun): TAddr; override;
  end;

  { a string value (function result, constant, concatenation) held in a scratch variable so that it can be indexed }
  TTempStr = class(TAddrExpr)
  public
    Src, Temp: TExpr;
    constructor Create(ASrc, ATemp: TExpr; AType: TType);
    function EvalA(C: TRun): TAddr; override;
    function IsLValue: Boolean; override;
  end;

  { p[i] of a PChar: the character i places after the one p points to }
  TPtrIndexAddr = class(TAddrExpr)
  public
    Base, Index: TExpr;
    constructor Create(ABase, AIndex: TExpr; AType: TType);
    function EvalA(C: TRun): TAddr; override;
  end;

  { a PChar used as a string }
  TPCharToStr = class(TExpr)
  public
    E: TExpr;
    constructor Create(AE: TExpr; AType: TType);
    procedure EvalS(C: TRun; out S: ShortString); override;
  end;

  { element of an open array parameter: the slot holds the address and the highest index }
  TOpenIndexAddr = class(TAddrExpr)
  public
    Slot, Index: TExpr;
    ElemSize: Integer;
    constructor Create(ASlot, AIndex: TExpr; AElemSize: Integer; AType: TType);
    function EvalA(C: TRun): TAddr; override;
  end;

  { the data of an open array parameter, for Move/FillChar/BlockRead and friends }
  TOpenData = class(TAddrExpr)
  public
    Slot: TExpr;
    constructor Create(ASlot: TExpr; AType: TType);
    function EvalA(C: TRun): TAddr; override;
  end;

  { High(a) of an open array parameter }
  TOpenHigh = class(TExpr)
  public
    Slot: TExpr;
    constructor Create(ASlot: TExpr; AType: TType);
    function EvalI(C: TRun): Int64; override;
  end;

  { same address, another type (variable typecast) }
  TRetype = class(TAddrExpr)
  public
    Base: TExpr;
    constructor Create(ABase: TExpr; AType: TType);
    function EvalA(C: TRun): TAddr; override;
  end;

  { an ordinal/real/pointer value seen as another type of the same class }
  TRetypeVal = class(TExpr)
  public
    E: TExpr;
    constructor Create(AE: TExpr; AType: TType);
    function EvalI(C: TRun): Int64; override;
    function EvalR(C: TRun): Double; override;
  end;

  { value of the variable at an address }
  TLoad = class(TExpr)
  public
    Addr: TExpr;
    constructor Create(AAddr: TExpr; AType: TType);
    function EvalI(C: TRun): Int64; override;
    function EvalR(C: TRun): Double; override;
    procedure EvalS(C: TRun; out S: ShortString); override;
    procedure EvalSet(C: TRun; var S: TSetVal); override;
  end;

  { fast paths: an integer variable that is global, or local to the running routine }
  TLoadGlobalInt = class(TExpr)
  public
    Addr: TAddr;
    Sz: Integer;
    Signed: Boolean;
    constructor Create(AAddr: TAddr; AType: TType);
    function EvalI(C: TRun): Int64; override;
  end;

  TLoadLocalInt = class(TExpr)
  public
    Offset: Integer;
    Sz: Integer;
    Signed: Boolean;
    constructor Create(AOffset: Integer; AType: TType);
    function EvalI(C: TRun): Int64; override;
  end;

  { @variable }
  TAddrOf = class(TExpr)
  public
    Target: TExpr;
    constructor Create(ATarget: TExpr; AType: TType);
    function EvalI(C: TRun): Int64; override;
  end;

  { ---- conversions ---- }
  TIntToReal = class(TExpr)
  public
    E: TExpr;
    constructor Create(AE: TExpr; AType: TType);
    function EvalR(C: TRun): Double; override;
  end;

  TCharToStr = class(TExpr)
  public
    E: TExpr;
    constructor Create(AE: TExpr; AType: TType);
    procedure EvalS(C: TRun; out S: ShortString); override;
  end;

  { an integer expression cut to the width of another type, or range checked }
  TIntCast = class(TExpr)
  public
    E: TExpr;
    Lo, Hi: Int64;
    Check: Boolean;
    Size: Integer;
    Signed: Boolean;
    constructor Create(AE: TExpr; AType: TType; ACheck: Boolean);
    function EvalI(C: TRun): Int64; override;
  end;

  { ---- operators ---- }
  TIntBin = class(TExpr)
  public
    Op: TArithOp;
    L, R: TExpr;
    Wrap: TWrap;
    constructor Create(AOp: TArithOp; AL, AR: TExpr; AWrap: TWrap; AType: TType);
    function EvalI(C: TRun): Int64; override;
  end;

  TIntUn = class(TExpr)
  public
    IsNot: Boolean;
    E: TExpr;
    Wrap: TWrap;
    constructor Create(AIsNot: Boolean; AE: TExpr; AWrap: TWrap; AType: TType);
    function EvalI(C: TRun): Int64; override;
  end;

  TRealBin = class(TExpr)
  public
    Op: Char;        // + - * /
    L, R: TExpr;
    constructor Create(AOp: Char; AL, AR: TExpr; AType: TType);
    function EvalR(C: TRun): Double; override;
  end;

  TRealNeg = class(TExpr)
  public
    E: TExpr;
    constructor Create(AE: TExpr; AType: TType);
    function EvalR(C: TRun): Double; override;
  end;

  TBoolBin = class(TExpr)
  public
    Op: Char;        // & | ^
    L, R: TExpr;
    constructor Create(AOp: Char; AL, AR: TExpr; AType: TType);
    function EvalI(C: TRun): Int64; override;
  end;

  TBoolNot = class(TExpr)
  public
    E: TExpr;
    constructor Create(AE: TExpr; AType: TType);
    function EvalI(C: TRun): Int64; override;
  end;

  TCmpInt = class(TExpr)
  public
    Op: TCmp;
    L, R: TExpr;
    constructor Create(AOp: TCmp; AL, AR: TExpr; AType: TType);
    function EvalI(C: TRun): Int64; override;
  end;

  TCmpReal = class(TExpr)
  public
    Op: TCmp;
    L, R: TExpr;
    constructor Create(AOp: TCmp; AL, AR: TExpr; AType: TType);
    function EvalI(C: TRun): Int64; override;
  end;

  TCmpStr = class(TExpr)
  public
    Op: TCmp;
    L, R: TExpr;
    constructor Create(AOp: TCmp; AL, AR: TExpr; AType: TType);
    function EvalI(C: TRun): Int64; override;
  end;

  TCmpSet = class(TExpr)
  public
    Op: TCmp;        // cEq, cNe, cLe (subset), cGe (superset)
    L, R: TExpr;
    constructor Create(AOp: TCmp; AL, AR: TExpr; AType: TType);
    function EvalI(C: TRun): Int64; override;
  end;

  TStrConcat = class(TExpr)
  public
    L, R: TExpr;
    constructor Create(AL, AR: TExpr; AType: TType);
    procedure EvalS(C: TRun; out S: ShortString); override;
  end;

  TSetBin = class(TExpr)
  public
    Op: Char;        // + - *
    L, R: TExpr;
    constructor Create(AOp: Char; AL, AR: TExpr; AType: TType);
    procedure EvalSet(C: TRun; var S: TSetVal); override;
  end;

  TSetIn = class(TExpr)
  public
    E, SetE: TExpr;
    constructor Create(AE, ASet: TExpr; AType: TType);
    function EvalI(C: TRun): Int64; override;
  end;

  TSetCons = class(TExpr)
  public
    Los, His: array of TExpr;       // His[i] = nil for a single element
    constructor Create(AType: TType);
    procedure Add(ALo, AHi: TExpr);
    procedure EvalSet(C: TRun; var S: TSetVal); override;
  end;

  { ---- calls ---- }
  TArg = class
  public
    Expr: TExpr;
    Mode: TParamMode;
    Typ: TType;              // nil: untyped var/const parameter (address only)
    Offset: Integer;
    IsOpen: Boolean;         // open array parameter: address and highest index are passed
    FromOpen: Boolean;       // the actual parameter is itself an open array parameter
    ElemSize: Integer;
    ActCount: Int64;         // number of elements of the actual array
  end;

  TCallExpr = class(TExpr)
  public
    Routine: TRoutine;
    Args: TObjectList;         // TArg (owned)
    CallerLevel: Integer;
    TempAddr: TExpr;           // where a record/array/set result is copied to
    SelfExpr: TExpr;           // method calls: the address of the object (also argument 0)
    ProcExpr: TExpr;           // call through a procedural value: evaluates to the routine's number
    VirtIndex: Integer;        // >= 0: pick the routine from the object's VMT
    SetVmtId: Integer;         // constructor called through a designator: store this type id in the VMT field
    VmtOff: Integer;
    IsCtor: Boolean;
    CtorOk: Boolean;
    constructor Create(ARoutine: TRoutine; ACallerLevel: Integer);
    destructor Destroy; override;
    procedure Invoke(C: TRun; out ResAddr: TAddr);
    function EvalI(C: TRun): Int64; override;
    function EvalR(C: TRun): Double; override;
    procedure EvalS(C: TRun; out S: ShortString); override;
    procedure EvalSet(C: TRun; var S: TSetVal); override;
    function EvalA(C: TRun): TAddr; override;
  end;

  { ---------------- statements ---------------- }
  TStmt = class
  public
    Line: Integer;
    constructor Create;
    function Run(C: TRun): TSig;
    function Exec(C: TRun): TSig; virtual; abstract;
  end;

  TNop = class(TStmt)
  public
    function Exec(C: TRun): TSig; override;
  end;

  TCompound = class(TStmt)
  public
    Items: array of TStmt;
    LabelIds, LabelIdx: array of Integer;     // labels in this statement list and the statement each one names
    procedure Add(S: TStmt);
    procedure AddLabel(Id: Integer);
    function Exec(C: TRun): TSig; override;
  end;

  TGoto = class(TStmt)
  public
    LabelId: Integer;
    function Exec(C: TRun): TSig; override;
  end;

  TAssign = class(TStmt)
  public
    Dst, Src: TExpr;
    constructor Create(ADst, ASrc: TExpr);
    function Exec(C: TRun): TSig; override;
  end;

  { a function call used as a statement; the result is dropped }
  TEvalStmt = class(TStmt)
  public
    E: TExpr;
    function Exec(C: TRun): TSig; override;
  end;

  TCallStmt = class(TStmt)
  public
    Call: TCallExpr;
    function Exec(C: TRun): TSig; override;
  end;

  TIf = class(TStmt)
  public
    Cond: TExpr;
    ThenS, ElseS: TStmt;
    function Exec(C: TRun): TSig; override;
  end;

  TWhile = class(TStmt)
  public
    Cond: TExpr;
    Body: TStmt;
    function Exec(C: TRun): TSig; override;
  end;

  TRepeat = class(TStmt)
  public
    Cond: TExpr;
    Body: TStmt;
    function Exec(C: TRun): TSig; override;
  end;

  TFor = class(TStmt)
  public
    VarAddr, First, Last: TExpr;
    Down: Boolean;
    Body: TStmt;
    function Exec(C: TRun): TSig; override;
  end;

  TCaseArm = class
  public
    Los, His: array of Int64;
    Body: TStmt;
  end;

  TCase = class(TStmt)
  public
    Sel: TExpr;
    Arms: TObjectList;
    ElseS: TStmt;
    constructor Create;
    destructor Destroy; override;
    function Exec(C: TRun): TSig; override;
  end;

  TSignal = class(TStmt)
  public
    Sig: TSig;
    constructor Create(ASig: TSig);
    function Exec(C: TRun): TSig; override;
  end;

function FrameAt(C: TRun; Hops: Integer): TAddr; inline;
function SetBitCount(const S: TSetVal): Integer;
procedure StoreValue(C: TRun; E: TExpr; Dst: TAddr; T: TType);

implementation

function FrameAt(C: TRun; Hops: Integer): TAddr;
begin
  Result := C.FP;
  while Hops > 0 do
  begin
    Result := TAddr(C.Mem.GetInt(Result, 4, False));
    Dec(Hops);
  end;
end;

function SetBitCount(const S: TSetVal): Integer;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 0 to 31 do
    for J := 0 to 7 do
      if (S[I] and (1 shl J)) <> 0 then Inc(Result);
end;

function IsSigned(T: TType): Boolean;
begin
  Result := (T.Kind = tyInt) and (T.Lo < 0);
end;

{ store the value of E into memory at Dst as type T }
procedure StoreValue(C: TRun; E: TExpr; Dst: TAddr; T: TType);
var
  S: ShortString;
  SV: TSetVal;
begin
  case T.ExprClass of
    ecInt: C.Mem.PutInt(Dst, T.Size, E.EvalI(C));
    ecReal: C.Mem.PutReal(Dst, T.RealKind, E.EvalR(C));
    ecStr:
      begin
        E.EvalS(C, S);
        C.Mem.PutStr(Dst, T.MaxLen, S);
      end;
    ecSet:
      begin
        FillChar(SV, SizeOf(SV), 0);
        E.EvalSet(C, SV);
        Move(SV, C.Mem.P(Dst, T.Size)^, T.Size);
      end;
    ecMem: C.Mem.Copy(E.EvalA(C), Dst, T.Size);
  end;
end;

{ ---------------- TRoutine ---------------- }

constructor TRoutine.Create;
begin
  inherited Create;
  Params := TObjectList.Create(True);
  VIndex := -1;
end;

destructor TRoutine.Destroy;
begin
  Params.Free;
  inherited Destroy;
end;

{ ---------------- PChar ---------------- }

constructor TPtrIndexAddr.Create(ABase, AIndex: TExpr; AType: TType);
begin
  inherited Create;
  Base := ABase;
  Index := AIndex;
  Typ := AType;
end;

function TPtrIndexAddr.EvalA(C: TRun): TAddr;
var
  B: Int64;
begin
  B := Base.EvalI(C);
  if B = 0 then raise EMKRuntime.CreateCode(204);
  Result := TAddr(B + Index.EvalI(C));
end;

constructor TPCharToStr.Create(AE: TExpr; AType: TType);
begin
  inherited Create;
  E := AE;
  Typ := AType;
end;

procedure TPCharToStr.EvalS(C: TRun; out S: ShortString);
var
  A: TAddr;
  N, B: Integer;
begin
  A := TAddr(E.EvalI(C));
  S := '';
  if A = 0 then Exit;
  N := 0;
  while N < 255 do
  begin
    B := Integer(C.Mem.GetInt(A + TAddr(N), 1, False));
    if B = 0 then Break;
    Inc(N);
    S[N] := Chr(B);
  end;
  SetLength(S, N);
end;

{ ---------------- open arrays ---------------- }

constructor TTempStr.Create(ASrc, ATemp: TExpr; AType: TType);
begin
  inherited Create;
  Src := ASrc;
  Temp := ATemp;
  Typ := AType;
end;

function TTempStr.EvalA(C: TRun): TAddr;
var
  S: ShortString;
begin
  Src.EvalS(C, S);
  Result := Temp.EvalA(C);
  C.Mem.PutStr(Result, 255, S);
end;

function TTempStr.IsLValue: Boolean;
begin
  Result := False;
end;

constructor TOpenIndexAddr.Create(ASlot, AIndex: TExpr; AElemSize: Integer; AType: TType);
begin
  inherited Create;
  Slot := ASlot;
  Index := AIndex;
  ElemSize := AElemSize;
  Typ := AType;
end;

function TOpenIndexAddr.EvalA(C: TRun): TAddr;
var
  S: TAddr;
  I, High: Int64;
begin
  S := Slot.EvalA(C);
  I := Index.EvalI(C);
  High := C.Mem.GetInt(S + 4, 4, True);
  if (I < 0) or (I > High) then raise EMKRuntime.CreateCode(201);
  Result := TAddr(C.Mem.GetInt(S, 4, False)) + TAddr(I * ElemSize);
end;

constructor TOpenData.Create(ASlot: TExpr; AType: TType);
begin
  inherited Create;
  Slot := ASlot;
  Typ := AType;
end;

function TOpenData.EvalA(C: TRun): TAddr;
begin
  Result := TAddr(C.Mem.GetInt(Slot.EvalA(C), 4, False));
end;

constructor TOpenHigh.Create(ASlot: TExpr; AType: TType);
begin
  inherited Create;
  Slot := ASlot;
  Typ := AType;
end;

function TOpenHigh.EvalI(C: TRun): Int64;
begin
  Result := C.Mem.GetInt(Slot.EvalA(C) + 4, 4, True);
end;

{ ---------------- TExpr ---------------- }

constructor TExpr.Create;
begin
  inherited Create;
  if NodePool <> nil then NodePool.Add(Self);
end;

function TExpr.EvalI(C: TRun): Int64;
begin
  Result := 0;
  raise Exception.Create('internal: expression is not an integer');
end;

function TExpr.EvalR(C: TRun): Double;
begin
  if Typ.ExprClass = ecInt then Exit(EvalI(C));
  raise Exception.Create('internal: expression is not a real');
end;

procedure TExpr.EvalS(C: TRun; out S: ShortString);
begin
  S := '';
  raise Exception.Create('internal: expression is not a string');
end;

procedure TExpr.EvalSet(C: TRun; var S: TSetVal);
begin
  raise Exception.Create('internal: expression is not a set');
end;

function TExpr.EvalA(C: TRun): TAddr;
begin
  Result := 0;
  raise Exception.Create('internal: expression has no address');
end;

function TExpr.IsConst: Boolean;
begin
  Result := False;
end;

function TExpr.IsLValue: Boolean;
begin
  Result := False;
end;

function TExpr.Cls: TExprClass;
begin
  Result := Typ.ExprClass;
end;

{ ---------------- constants ---------------- }

constructor TConstInt.Create(AValue: Int64; AType: TType);
begin
  inherited Create;
  Value := AValue;
  Typ := AType;
end;

function TConstInt.EvalI(C: TRun): Int64;
begin
  Result := Value;
end;

function TConstInt.IsConst: Boolean;
begin
  Result := True;
end;

constructor TConstReal.Create(AValue: Double; AType: TType);
begin
  inherited Create;
  Value := AValue;
  Typ := AType;
end;

function TConstReal.EvalR(C: TRun): Double;
begin
  Result := Value;
end;

function TConstReal.IsConst: Boolean;
begin
  Result := True;
end;

constructor TConstStr.Create(const AValue: ShortString; AType: TType);
begin
  inherited Create;
  Value := AValue;
  Typ := AType;
end;

procedure TConstStr.EvalS(C: TRun; out S: ShortString);
begin
  S := Value;
end;

function TConstStr.IsConst: Boolean;
begin
  Result := True;
end;

constructor TConstSet.Create(const AValue: TSetVal; AType: TType);
begin
  inherited Create;
  Value := AValue;
  Typ := AType;
end;

procedure TConstSet.EvalSet(C: TRun; var S: TSetVal);
begin
  S := Value;
end;

function TConstSet.IsConst: Boolean;
begin
  Result := True;
end;

{ ---------------- addresses ---------------- }

function TAddrExpr.IsLValue: Boolean;
begin
  Result := True;
end;

constructor TGlobalAddr.Create(AAddr: TAddr; AType: TType);
begin
  inherited Create;
  Addr := AAddr;
  Typ := AType;
end;

function TGlobalAddr.EvalA(C: TRun): TAddr;
begin
  Result := Addr;
end;

constructor TLocalAddr.Create(AOffset, AHops: Integer; AType: TType);
begin
  inherited Create;
  Offset := AOffset;
  Hops := AHops;
  Typ := AType;
end;

function TLocalAddr.EvalA(C: TRun): TAddr;
begin
  Result := FrameAt(C, Hops) + TAddr(Offset);
end;

constructor TVarParamAddr.Create(AOffset, AHops: Integer; AType: TType);
begin
  inherited Create;
  Offset := AOffset;
  Hops := AHops;
  Typ := AType;
end;

function TVarParamAddr.EvalA(C: TRun): TAddr;
begin
  Result := TAddr(C.Mem.GetInt(FrameAt(C, Hops) + TAddr(Offset), 4, False));
end;

constructor TDerefAddr.Create(APtr: TExpr; AType: TType);
begin
  inherited Create;
  Ptr := APtr;
  Typ := AType;
end;

function TDerefAddr.EvalA(C: TRun): TAddr;
begin
  Result := TAddr(Ptr.EvalI(C));
  if Result = 0 then raise EMKRuntime.CreateCode(204);
end;

constructor TFieldAddr.Create(ABase: TExpr; AOffset: Integer; AType: TType);
begin
  inherited Create;
  Base := ABase;
  Offset := AOffset;
  Typ := AType;
end;

function TFieldAddr.EvalA(C: TRun): TAddr;
begin
  Result := Base.EvalA(C) + TAddr(Offset);
end;

constructor TIndexAddr.Create(ABase, AIndex: TExpr; ALo, AHi: Int64; AElemSize: Integer; AType: TType);
begin
  inherited Create;
  Base := ABase;
  Index := AIndex;
  Lo := ALo;
  Hi := AHi;
  ElemSize := AElemSize;
  Typ := AType;
end;

function TIndexAddr.EvalA(C: TRun): TAddr;
var
  I: Int64;
begin
  Result := Base.EvalA(C);
  I := Index.EvalI(C);
  if (I < Lo) or (I > Hi) then raise EMKRuntime.CreateCode(201);
  Result := Result + TAddr((I - Lo) * ElemSize);
end;

constructor TStrElemAddr.Create(ABase, AIndex: TExpr; AMaxLen: Integer; AType: TType);
begin
  inherited Create;
  Base := ABase;
  Index := AIndex;
  MaxLen := AMaxLen;
  Typ := AType;
end;

function TStrElemAddr.EvalA(C: TRun): TAddr;
var
  I: Int64;
begin
  Result := Base.EvalA(C);
  I := Index.EvalI(C);
  if (I < 0) or (I > MaxLen) then raise EMKRuntime.CreateCode(201);
  Result := Result + TAddr(I);
end;

constructor TRetype.Create(ABase: TExpr; AType: TType);
begin
  inherited Create;
  Base := ABase;
  Typ := AType;
end;

function TRetype.EvalA(C: TRun): TAddr;
begin
  Result := Base.EvalA(C);
end;

{ ---------------- loads ---------------- }

constructor TRetypeVal.Create(AE: TExpr; AType: TType);
begin
  inherited Create;
  E := AE;
  Typ := AType;
end;

function TRetypeVal.EvalI(C: TRun): Int64;
begin
  Result := E.EvalI(C);
end;

function TRetypeVal.EvalR(C: TRun): Double;
begin
  Result := E.EvalR(C);
end;

constructor TLoad.Create(AAddr: TExpr; AType: TType);
begin
  inherited Create;
  Addr := AAddr;
  Typ := AType;
end;

function TLoad.EvalI(C: TRun): Int64;
begin
  Result := C.Mem.GetInt(Addr.EvalA(C), Typ.Size, IsSigned(Typ));
end;

function TLoad.EvalR(C: TRun): Double;
begin
  Result := C.Mem.GetReal(Addr.EvalA(C), Typ.RealKind);
end;

procedure TLoad.EvalS(C: TRun; out S: ShortString);
begin
  C.Mem.GetStr(Addr.EvalA(C), S);
end;

procedure TLoad.EvalSet(C: TRun; var S: TSetVal);
begin
  FillChar(S, SizeOf(S), 0);
  Move(C.Mem.P(Addr.EvalA(C), Typ.Size)^, S, Typ.Size);
end;

constructor TLoadGlobalInt.Create(AAddr: TAddr; AType: TType);
begin
  inherited Create;
  Addr := AAddr;
  Typ := AType;
  Sz := AType.Size;
  Signed := IsSigned(AType);
end;

function TLoadGlobalInt.EvalI(C: TRun): Int64;
begin
  Result := C.Mem.GetInt(Addr, Sz, Signed);
end;

constructor TLoadLocalInt.Create(AOffset: Integer; AType: TType);
begin
  inherited Create;
  Offset := AOffset;
  Typ := AType;
  Sz := AType.Size;
  Signed := IsSigned(AType);
end;

function TLoadLocalInt.EvalI(C: TRun): Int64;
begin
  Result := C.Mem.GetInt(C.FP + TAddr(Offset), Sz, Signed);
end;

constructor TAddrOf.Create(ATarget: TExpr; AType: TType);
begin
  inherited Create;
  Target := ATarget;
  Typ := AType;
end;

function TAddrOf.EvalI(C: TRun): Int64;
begin
  Result := Target.EvalA(C);
end;

{ ---------------- conversions ---------------- }

constructor TIntToReal.Create(AE: TExpr; AType: TType);
begin
  inherited Create;
  E := AE;
  Typ := AType;
end;

function TIntToReal.EvalR(C: TRun): Double;
begin
  Result := E.EvalI(C);
end;

constructor TCharToStr.Create(AE: TExpr; AType: TType);
begin
  inherited Create;
  E := AE;
  Typ := AType;
end;

procedure TCharToStr.EvalS(C: TRun; out S: ShortString);
begin
  S := Chr(Byte(E.EvalI(C)));
end;

constructor TIntCast.Create(AE: TExpr; AType: TType; ACheck: Boolean);
begin
  inherited Create;
  E := AE;
  Typ := AType;
  Check := ACheck;
  Lo := AType.Lo;
  Hi := AType.Hi;
  Size := AType.Size;
  Signed := IsSigned(AType);
end;

function TIntCast.EvalI(C: TRun): Int64;
begin
  Result := E.EvalI(C);
  if Check then
  begin
    if (Result < Lo) or (Result > Hi) then raise EMKRuntime.CreateCode(201);
    Exit;
  end;
  case Size of
    1: if Signed then Result := ShortInt(Result) else Result := Byte(Result);
    2: if Signed then Result := SmallInt(Result) else Result := Word(Result);
    4: if Signed then Result := LongInt(Result) else Result := LongWord(Result);
  end;
end;

{ ---------------- operators ---------------- }

function Wrapped(V: Int64; W: TWrap): Int64; inline;
begin
  case W of
    wI16: Result := SmallInt(V);
    wU16: Result := Word(V);
    wI32: Result := LongInt(V);
  else
    Result := V;
  end;
end;

constructor TIntBin.Create(AOp: TArithOp; AL, AR: TExpr; AWrap: TWrap; AType: TType);
begin
  inherited Create;
  Op := AOp;
  L := AL;
  R := AR;
  Wrap := AWrap;
  Typ := AType;
end;

function TIntBin.EvalI(C: TRun): Int64;
var
  A, B: Int64;
begin
  A := L.EvalI(C);
  B := R.EvalI(C);
  case Op of
    aoAdd: Result := A + B;
    aoSub: Result := A - B;
    aoMul: Result := A * B;
    aoDiv:
      begin
        if B = 0 then raise EMKRuntime.CreateCode(200);
        Result := A div B;
      end;
    aoMod:
      begin
        if B = 0 then raise EMKRuntime.CreateCode(200);
        Result := A mod B;
        Exit;
      end;
    aoAnd: Result := A and B;
    aoOr: Result := A or B;
    aoXor: Result := A xor B;
    aoShl:
      begin
        if (B < 0) or (B > 63) then Result := 0 else Result := A shl B;
      end;
    aoShr:
      begin
        if (B < 0) or (B > 63) then Result := 0
        else if Wrap = wU16 then Result := (A and $FFFF) shr B
        else Result := SarInt64(A, B);
      end;
  else
    Result := 0;
  end;
  Result := Wrapped(Result, Wrap);
end;

constructor TIntUn.Create(AIsNot: Boolean; AE: TExpr; AWrap: TWrap; AType: TType);
begin
  inherited Create;
  IsNot := AIsNot;
  E := AE;
  Wrap := AWrap;
  Typ := AType;
end;

function TIntUn.EvalI(C: TRun): Int64;
begin
  if IsNot then Result := not E.EvalI(C) else Result := -E.EvalI(C);
  Result := Wrapped(Result, Wrap);
end;

constructor TRealBin.Create(AOp: Char; AL, AR: TExpr; AType: TType);
begin
  inherited Create;
  Op := AOp;
  L := AL;
  R := AR;
  Typ := AType;
end;

function TRealBin.EvalR(C: TRun): Double;
var
  B: Double;
begin
  Result := L.EvalR(C);
  B := R.EvalR(C);
  case Op of
    '+': Result := Result + B;
    '-': Result := Result - B;
    '*': Result := Result * B;
  else
    begin
      if B = 0 then raise EMKRuntime.CreateCode(200);
      Result := Result / B;
    end;
  end;
end;

constructor TRealNeg.Create(AE: TExpr; AType: TType);
begin
  inherited Create;
  E := AE;
  Typ := AType;
end;

function TRealNeg.EvalR(C: TRun): Double;
begin
  Result := -E.EvalR(C);
end;

constructor TBoolBin.Create(AOp: Char; AL, AR: TExpr; AType: TType);
begin
  inherited Create;
  Op := AOp;
  L := AL;
  R := AR;
  Typ := AType;
end;

function TBoolBin.EvalI(C: TRun): Int64;
begin
  case Op of
    '&': if L.EvalI(C) <> 0 then Result := R.EvalI(C) else Result := 0;
    '|': if L.EvalI(C) <> 0 then Result := 1 else Result := R.EvalI(C);
  else
    if (L.EvalI(C) <> 0) <> (R.EvalI(C) <> 0) then Result := 1 else Result := 0;
  end;
end;

constructor TBoolNot.Create(AE: TExpr; AType: TType);
begin
  inherited Create;
  E := AE;
  Typ := AType;
end;

function TBoolNot.EvalI(C: TRun): Int64;
begin
  if E.EvalI(C) = 0 then Result := 1 else Result := 0;
end;

function CmpResult(Op: TCmp; Diff: Integer): Int64; inline;
begin
  case Op of
    cEq: Result := Ord(Diff = 0);
    cNe: Result := Ord(Diff <> 0);
    cLt: Result := Ord(Diff < 0);
    cGt: Result := Ord(Diff > 0);
    cLe: Result := Ord(Diff <= 0);
  else
    Result := Ord(Diff >= 0);
  end;
end;

constructor TCmpInt.Create(AOp: TCmp; AL, AR: TExpr; AType: TType);
begin
  inherited Create;
  Op := AOp;
  L := AL;
  R := AR;
  Typ := AType;
end;

function TCmpInt.EvalI(C: TRun): Int64;
var
  A, B: Int64;
begin
  A := L.EvalI(C);
  B := R.EvalI(C);
  if A < B then Result := CmpResult(Op, -1)
  else if A > B then Result := CmpResult(Op, 1)
  else Result := CmpResult(Op, 0);
end;

constructor TCmpReal.Create(AOp: TCmp; AL, AR: TExpr; AType: TType);
begin
  inherited Create;
  Op := AOp;
  L := AL;
  R := AR;
  Typ := AType;
end;

function TCmpReal.EvalI(C: TRun): Int64;
var
  A, B: Double;
begin
  A := L.EvalR(C);
  B := R.EvalR(C);
  if A < B then Result := CmpResult(Op, -1)
  else if A > B then Result := CmpResult(Op, 1)
  else Result := CmpResult(Op, 0);
end;

constructor TCmpStr.Create(AOp: TCmp; AL, AR: TExpr; AType: TType);
begin
  inherited Create;
  Op := AOp;
  L := AL;
  R := AR;
  Typ := AType;
end;

function TCmpStr.EvalI(C: TRun): Int64;
var
  A, B: ShortString;
  I, N, D: Integer;
begin
  L.EvalS(C, A);
  R.EvalS(C, B);
  N := Length(A);
  if Length(B) < N then N := Length(B);
  D := 0;
  for I := 1 to N do
    if A[I] <> B[I] then
    begin
      if Byte(A[I]) < Byte(B[I]) then D := -1 else D := 1;
      Break;
    end;
  if D = 0 then
  begin
    if Length(A) < Length(B) then D := -1 else if Length(A) > Length(B) then D := 1;
  end;
  Result := CmpResult(Op, D);
end;

constructor TCmpSet.Create(AOp: TCmp; AL, AR: TExpr; AType: TType);
begin
  inherited Create;
  Op := AOp;
  L := AL;
  R := AR;
  Typ := AType;
end;

function TCmpSet.EvalI(C: TRun): Int64;
var
  A, B: TSetVal;
  I: Integer;
  Sub, Sup: Boolean;
begin
  FillChar(A, SizeOf(A), 0);
  FillChar(B, SizeOf(B), 0);
  L.EvalSet(C, A);
  R.EvalSet(C, B);
  Sub := True;
  Sup := True;
  for I := 0 to 31 do
  begin
    if (A[I] and not B[I]) <> 0 then Sub := False;
    if (B[I] and not A[I]) <> 0 then Sup := False;
  end;
  case Op of
    cEq: Result := Ord(Sub and Sup);
    cNe: Result := Ord(not (Sub and Sup));
    cLe: Result := Ord(Sub);
  else
    Result := Ord(Sup);
  end;
end;

constructor TStrConcat.Create(AL, AR: TExpr; AType: TType);
begin
  inherited Create;
  L := AL;
  R := AR;
  Typ := AType;
end;

procedure TStrConcat.EvalS(C: TRun; out S: ShortString);
var
  B: ShortString;
begin
  L.EvalS(C, S);
  R.EvalS(C, B);
  if Length(S) + Length(B) > 255 then B := Copy(B, 1, 255 - Length(S));
  S := S + B;
end;

constructor TSetBin.Create(AOp: Char; AL, AR: TExpr; AType: TType);
begin
  inherited Create;
  Op := AOp;
  L := AL;
  R := AR;
  Typ := AType;
end;

procedure TSetBin.EvalSet(C: TRun; var S: TSetVal);
var
  B: TSetVal;
  I: Integer;
begin
  FillChar(S, SizeOf(S), 0);
  FillChar(B, SizeOf(B), 0);
  L.EvalSet(C, S);
  R.EvalSet(C, B);
  for I := 0 to 31 do
    case Op of
      '+': S[I] := S[I] or B[I];
      '-': S[I] := S[I] and not B[I];
    else
      S[I] := S[I] and B[I];
    end;
end;

constructor TSetIn.Create(AE, ASet: TExpr; AType: TType);
begin
  inherited Create;
  E := AE;
  SetE := ASet;
  Typ := AType;
end;

function TSetIn.EvalI(C: TRun): Int64;
var
  V: Int64;
  S: TSetVal;
begin
  V := E.EvalI(C);
  FillChar(S, SizeOf(S), 0);
  SetE.EvalSet(C, S);
  if (V < 0) or (V > 255) then Exit(0);
  Result := Ord((S[V shr 3] and (1 shl (V and 7))) <> 0);
end;

constructor TSetCons.Create(AType: TType);
begin
  inherited Create;
  Typ := AType;
end;

procedure TSetCons.Add(ALo, AHi: TExpr);
begin
  SetLength(Los, Length(Los) + 1);
  SetLength(His, Length(His) + 1);
  Los[High(Los)] := ALo;
  His[High(His)] := AHi;
end;

procedure TSetCons.EvalSet(C: TRun; var S: TSetVal);
var
  I: Integer;
  A, B, V: Int64;
begin
  FillChar(S, SizeOf(S), 0);
  for I := 0 to High(Los) do
  begin
    A := Los[I].EvalI(C);
    if His[I] = nil then B := A else B := His[I].EvalI(C);
    if A < 0 then A := 0;
    if B > 255 then B := 255;
    for V := A to B do S[V shr 3] := S[V shr 3] or (1 shl (V and 7));
  end;
end;

{ ---------------- calls ---------------- }

constructor TCallExpr.Create(ARoutine: TRoutine; ACallerLevel: Integer);
begin
  inherited Create;
  Routine := ARoutine;
  CallerLevel := ACallerLevel;
  Args := TObjectList.Create(True);
  VirtIndex := -1;
  VmtOff := -1;
  if ARoutine.Ret <> nil then Typ := ARoutine.Ret;
end;

destructor TCallExpr.Destroy;
begin
  Args.Free;
  inherited Destroy;
end;

procedure TCallExpr.Invoke(C: TRun; out ResAddr: TAddr);
var
  NewFP, SavedSP, SavedFP, Link, SelfA, DataA, SlotA: TAddr;
  I, First, Id, NCopies: Integer;
  A: TArg;
  R: TRoutine;
  High: Int64;
  Copies: array of TAddr;
begin
  R := Routine;
  First := 0;
  SelfA := 0;
  NCopies := 0;
  if ProcExpr <> nil then
  begin
    Id := Integer(ProcExpr.EvalI(C));
    if (Id <= 0) or (Id > C.ProcTable.Count) then raise EMKRuntime.CreateCode(204);
    R := TRoutine(C.ProcTable[Id - 1]);
  end;
  if SelfExpr <> nil then
  begin
    SelfA := SelfExpr.EvalA(C);
    if SetVmtId > 0 then C.Mem.PutInt(SelfA + TAddr(VmtOff), 2, SetVmtId);
    if VirtIndex >= 0 then
    begin
      Id := Integer(C.Mem.GetInt(SelfA + TAddr(VmtOff), 2, False));
      if (Id <= 0) or (Id > C.ObjTypes.Count) then raise EMKRuntime.CreateCode(204);
      R := TRoutine(TType(C.ObjTypes[Id - 1]).Vtab[VirtIndex]);
    end;
    First := 1;                          // argument 0 is Self
  end;
  if C.Depth >= C.MaxDepth then raise EMKRuntime.CreateCode(202);
  if C.SP < TAddr(R.FrameSize) + C.Mem.StackBase then raise EMKRuntime.CreateCode(202);
  NewFP := C.SP - TAddr(R.FrameSize);
  SavedSP := C.SP;
  SavedFP := C.FP;
  C.Mem.Fill(NewFP, R.FrameSize, 0);
  C.SP := NewFP;
  try
    if SelfExpr <> nil then C.Mem.PutInt(NewFP + 8, 4, SelfA);
    for I := First to Args.Count - 1 do
    begin
      A := TArg(Args[I]);
      if A.IsOpen then
      begin
        if A.FromOpen then
        begin
          SlotA := A.Expr.EvalA(C);
          DataA := TAddr(C.Mem.GetInt(SlotA, 4, False));
          High := C.Mem.GetInt(SlotA + 4, 4, True);
        end
        else
        begin
          DataA := A.Expr.EvalA(C);
          High := A.ActCount - 1;
        end;
        if A.Mode = pmValue then
        begin
          { a value parameter gets a private copy, released when the call ends }
          SlotA := C.Mem.Alloc(LongWord((High + 1) * A.ElemSize));
          C.Mem.Copy(DataA, SlotA, LongWord((High + 1) * A.ElemSize));
          DataA := SlotA;
          SetLength(Copies, NCopies + 1);
          Copies[NCopies] := SlotA;
          Inc(NCopies);
        end;
        C.Mem.PutInt(NewFP + TAddr(A.Offset), 4, DataA);
        C.Mem.PutInt(NewFP + TAddr(A.Offset) + 4, 4, High);
      end
      else if (A.Mode = pmVar) or (A.Typ = nil) then
        C.Mem.PutInt(NewFP + TAddr(A.Offset), 4, A.Expr.EvalA(C))
      else
        StoreValue(C, A.Expr, NewFP + TAddr(A.Offset), A.Typ);
    end;
    { static link: the frame of the routine this one is declared in }
    Link := SavedFP;
    I := CallerLevel - (R.Level - 1);
    while I > 0 do
    begin
      Link := TAddr(C.Mem.GetInt(Link, 4, False));
      Dec(I);
    end;
    C.Mem.PutInt(NewFP, 4, Link);
    C.FP := NewFP;
    Inc(C.Depth);
    C.Tick;
    if R.Body <> nil then R.Body.Run(C);
  finally
    Dec(C.Depth);
    C.FP := SavedFP;
    C.SP := SavedSP;
    for I := 0 to NCopies - 1 do C.Mem.FreeBlock(Copies[I]);
  end;
  if IsCtor then
  begin
    CtorOk := not C.Failed;
    C.Failed := False;
  end;
  ResAddr := NewFP + TAddr(R.ResultOffset);
end;

function TCallExpr.EvalI(C: TRun): Int64;
var
  A: TAddr;
begin
  Invoke(C, A);
  if IsCtor then Exit(Ord(CtorOk));
  if Typ = nil then Exit(0);
  Result := C.Mem.GetInt(A, Typ.Size, IsSigned(Typ));
end;

function TCallExpr.EvalR(C: TRun): Double;
var
  A: TAddr;
begin
  Invoke(C, A);
  Result := C.Mem.GetReal(A, Typ.RealKind);
end;

procedure TCallExpr.EvalS(C: TRun; out S: ShortString);
var
  A: TAddr;
begin
  Invoke(C, A);
  C.Mem.GetStr(A, S);
end;

procedure TCallExpr.EvalSet(C: TRun; var S: TSetVal);
var
  A: TAddr;
begin
  Invoke(C, A);
  FillChar(S, SizeOf(S), 0);
  Move(C.Mem.P(A, Typ.Size)^, S, Typ.Size);
end;

function TCallExpr.EvalA(C: TRun): TAddr;
var
  A, T: TAddr;
begin
  if TempAddr = nil then raise Exception.Create('internal: the result of this call has no address');
  Invoke(C, A);
  T := TempAddr.EvalA(C);
  C.Mem.Copy(A, T, Typ.Size);
  Result := T;
end;

{ ---------------- statements ---------------- }

constructor TStmt.Create;
begin
  inherited Create;
  if NodePool <> nil then NodePool.Add(Self);
end;

function TStmt.Run(C: TRun): TSig;
begin
  C.LineNo := Line;
  Result := Exec(C);
end;

function TNop.Exec(C: TRun): TSig;
begin
  Result := sgNone;
end;

procedure TCompound.Add(S: TStmt);
begin
  SetLength(Items, Length(Items) + 1);
  Items[High(Items)] := S;
end;

procedure TCompound.AddLabel(Id: Integer);
begin
  SetLength(LabelIds, Length(LabelIds) + 1);
  SetLength(LabelIdx, Length(LabelIdx) + 1);
  LabelIds[High(LabelIds)] := Id;
  LabelIdx[High(LabelIdx)] := Length(Items);       // the next statement added is the one the label names
end;

function TCompound.Exec(C: TRun): TSig;
var
  I, J: Integer;
begin
  I := 0;
  while I < Length(Items) do
  begin
    Result := Items[I].Run(C);
    if Result <> sgNone then
    begin
      if (Result = sgGoto) and (Length(LabelIds) > 0) then
      begin
        for J := 0 to High(LabelIds) do
          if LabelIds[J] = C.GotoLabel then
          begin
            I := LabelIdx[J];
            C.Tick;                                  // a goto loop still honours limits and Break
            Result := sgNone;
            Break;
          end;
        if Result = sgNone then Continue;
      end;
      Exit;
    end;
    Inc(I);
  end;
  Result := sgNone;
end;

function TGoto.Exec(C: TRun): TSig;
begin
  C.GotoLabel := LabelId;
  Result := sgGoto;
end;

constructor TAssign.Create(ADst, ASrc: TExpr);
begin
  inherited Create;
  Dst := ADst;
  Src := ASrc;
end;

function TAssign.Exec(C: TRun): TSig;
var
  A: TAddr;
begin
  { the right side is evaluated first, like Turbo Pascal does for simple values }
  case Dst.Typ.ExprClass of
    ecInt:
      begin
        A := 0;
        C.Mem.PutInt(Dst.EvalA(C), Dst.Typ.Size, Src.EvalI(C));
        Exit(sgNone);
      end;
  end;
  A := Dst.EvalA(C);
  StoreValue(C, Src, A, Dst.Typ);
  Result := sgNone;
end;

function TEvalStmt.Exec(C: TRun): TSig;
begin
  E.EvalI(C);
  Result := sgNone;
end;

function TCallStmt.Exec(C: TRun): TSig;
var
  A: TAddr;
begin
  Call.Invoke(C, A);
  Result := sgNone;
end;

function TIf.Exec(C: TRun): TSig;
begin
  if Cond.EvalI(C) <> 0 then
    Result := ThenS.Run(C)
  else if ElseS <> nil then
    Result := ElseS.Run(C)
  else
    Result := sgNone;
end;

function TWhile.Exec(C: TRun): TSig;
begin
  Result := sgNone;
  while Cond.EvalI(C) <> 0 do
  begin
    Result := Body.Run(C);
    if Result <> sgNone then
    begin
      if Result = sgBreak then begin Result := sgNone; Break; end;
      if Result <> sgContinue then Exit;
      Result := sgNone;
    end;
    C.Tick;
  end;
end;

function TRepeat.Exec(C: TRun): TSig;
begin
  Result := sgNone;
  repeat
    Result := Body.Run(C);
    if Result <> sgNone then
    begin
      if Result = sgBreak then begin Result := sgNone; Break; end;
      if Result <> sgContinue then Exit;
      Result := sgNone;
    end;
    C.Tick;
  until Cond.EvalI(C) <> 0;
end;

function TFor.Exec(C: TRun): TSig;
var
  V, E: Int64;
  A: TAddr;
  Sz: Integer;
begin
  Result := sgNone;
  V := First.EvalI(C);
  E := Last.EvalI(C);
  A := VarAddr.EvalA(C);
  Sz := VarAddr.Typ.Size;
  while (Down and (V >= E)) or ((not Down) and (V <= E)) do
  begin
    C.Mem.PutInt(A, Sz, V);
    Result := Body.Run(C);
    if Result <> sgNone then
    begin
      if Result = sgBreak then begin Result := sgNone; Break; end;
      if Result <> sgContinue then Exit;
      Result := sgNone;
    end;
    C.Tick;
    if Down then Dec(V) else Inc(V);
  end;
end;

constructor TCase.Create;
begin
  inherited Create;
  Arms := TObjectList.Create(True);
end;

destructor TCase.Destroy;
begin
  Arms.Free;
  inherited Destroy;
end;

function TCase.Exec(C: TRun): TSig;
var
  V: Int64;
  I, J: Integer;
  Arm: TCaseArm;
begin
  V := Sel.EvalI(C);
  for I := 0 to Arms.Count - 1 do
  begin
    Arm := TCaseArm(Arms[I]);
    for J := 0 to High(Arm.Los) do
      if (V >= Arm.Los[J]) and (V <= Arm.His[J]) then Exit(Arm.Body.Run(C));
  end;
  if ElseS <> nil then Exit(ElseS.Run(C));
  Result := sgNone;
end;

constructor TSignal.Create(ASig: TSig);
begin
  inherited Create;
  Sig := ASig;
end;

function TSignal.Exec(C: TRun): TSig;
begin
  Result := Sig;
end;

end.
