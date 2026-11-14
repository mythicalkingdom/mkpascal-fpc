unit mkp_types;
// Type descriptors.  Every Pascal type knows its size in bytes in the Turbo Pascal layout, because
// variables live in a byte addressed memory (see mkp_mem).
{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, contnrs;

type
  TTypeKind = (tyInt, tyBool, tyChar, tyEnum, tyReal, tyString, tyArray, tyRecord, tySet,
               tyPtr, tyFile, tyProc, tyObject, tyNil, tyVoid, tyUntyped);

  TRealKind = (rkReal6, rkSingle, rkDouble, rkExtended, rkComp);

  { how an expression of a type is evaluated }
  TExprClass = (ecInt, ecReal, ecStr, ecSet, ecMem, ecVoid);

  TType = class;

  TField = class
  public
    Name: string;
    Typ: TType;
    Offset: Integer;
  end;

  TParamMode = (pmValue, pmVar, pmConst);

  TParamDesc = class
  public
    Name: string;
    Typ: TType;          // nil for an untyped var/const parameter
    Mode: TParamMode;
    Offset: Integer;     // offset in the callee frame
  end;

  TType = class
  public
    Kind: TTypeKind;
    Name: string;
    Size: Integer;
    // ordinals (tyInt, tyBool, tyChar, tyEnum): the value range
    Lo, Hi: Int64;
    Host: TType;               // subrange: the type it is a range of
    EnumNames: TStringList;
    RealKind: TRealKind;
    MaxLen: Integer;           // tyString: declared maximum length
    Elem: TType;               // tyArray element, tyFile element (nil = untyped / text)
    Index: TType;              // tyArray index type (ordinal)
    Fields: TObjectList;       // tyRecord and tyObject: TField
    Base: TType;               // tyPtr target, tySet base
    BaseName: string;          // forward pointer target name until resolved
    IsText: Boolean;           // tyFile: a Text file
    Params: TObjectList;       // tyProc: TParamDesc
    Ret: TType;                // tyProc: function result (nil for procedures)
    Parent: TType;             // tyObject: ancestor
    Methods: TStringList;      // tyObject: own methods (Objects = routines, owned by the compiler)
    Vtab: TList;               // tyObject: virtual methods by slot number (routines)
    VmtOff: Integer;           // tyObject: offset of the VMT pointer, -1 if none
    VmtId: Integer;            // tyObject: number of this type in the run time type table
    constructor Create(AKind: TTypeKind);
    destructor Destroy; override;
    function IsOrdinal: Boolean;
    function ExprClass: TExprClass;
    function FindField(const AName: string): TField;
  end;

  { owns every type created while compiling }
  TTypeStore = class
  private
    FList: TObjectList;
  public
    // predeclared
    TInteger, TShortInt, TByte, TWord, TLongInt, TBoolean, TChar, TString, TText, TPointer, TNil, TVoid,
    TReal, TSingle, TDouble, TExtended, TComp, TUntyped: TType;
    constructor Create;
    destructor Destroy; override;
    function NewType(AKind: TTypeKind): TType;
    function IntType(const AName: string; ALo, AHi: Int64; ASize: Integer): TType;
    function Subrange(AHost: TType; ALo, AHi: Int64): TType;
    function StringType(AMax: Integer): TType;
    function ArrayType(AIndex, AElem: TType): TType;
    function SetType(ABase: TType): TType;
    function PtrType(ABase: TType): TType;
    function FileType(AElem: TType): TType;
    function EnumType(Names: TStrings): TType;
    function IntTypeFor(ALo, AHi: Int64): TType;
  end;

function HostOf(T: TType): TType;
function SizeOfSubrange(Lo, Hi: Int64): Integer;
function SameType(A, B: TType): Boolean;
function Assignable(Dst, Src: TType): Boolean;
function IsDescendant(A, B: TType): Boolean;
function TypeName(T: TType): string;
function ProcCompat(A, B: TType): Boolean;

implementation

constructor TType.Create(AKind: TTypeKind);
begin
  inherited Create;
  Kind := AKind;
  VmtOff := -1;
  case AKind of
    tyRecord, tyObject: Fields := TObjectList.Create(True);
    tyProc: Params := TObjectList.Create(True);
  end;
  if AKind = tyEnum then EnumNames := TStringList.Create;
  if AKind = tyObject then
  begin
    Methods := TStringList.Create;
    Methods.CaseSensitive := False;
    Vtab := TList.Create;
  end;
end;

destructor TType.Destroy;
begin
  Fields.Free;
  Params.Free;
  EnumNames.Free;
  Methods.Free;
  Vtab.Free;
  inherited Destroy;
end;

function TType.IsOrdinal: Boolean;
begin
  Result := Kind in [tyInt, tyBool, tyChar, tyEnum];
end;

function TType.ExprClass: TExprClass;
begin
  case Kind of
    tyInt, tyBool, tyChar, tyEnum, tyPtr, tyProc, tyNil: Result := ecInt;
    tyReal: Result := ecReal;
    tyString: Result := ecStr;
    tySet: Result := ecSet;
    tyArray, tyRecord, tyObject, tyFile: Result := ecMem;
  else
    Result := ecVoid;
  end;
end;

function TType.FindField(const AName: string): TField;
var
  I: Integer;
begin
  Result := nil;
  if Fields = nil then Exit;
  for I := 0 to Fields.Count - 1 do
    if SameText(TField(Fields[I]).Name, AName) then Exit(TField(Fields[I]));
end;

{ ---------------- TTypeStore ---------------- }

constructor TTypeStore.Create;
begin
  inherited Create;
  FList := TObjectList.Create(True);
  TShortInt := IntType('ShortInt', -128, 127, 1);
  TByte := IntType('Byte', 0, 255, 1);
  TInteger := IntType('Integer', -32768, 32767, 2);
  TWord := IntType('Word', 0, 65535, 2);
  TLongInt := IntType('LongInt', -2147483648, 2147483647, 4);
  TBoolean := NewType(tyBool);
  TBoolean.Name := 'Boolean'; TBoolean.Size := 1; TBoolean.Lo := 0; TBoolean.Hi := 1;
  TChar := NewType(tyChar);
  TChar.Name := 'Char'; TChar.Size := 1; TChar.Lo := 0; TChar.Hi := 255;
  TReal := NewType(tyReal);
  TReal.Name := 'Real'; TReal.Size := 6; TReal.RealKind := rkReal6;
  TSingle := NewType(tyReal);
  TSingle.Name := 'Single'; TSingle.Size := 4; TSingle.RealKind := rkSingle;
  TDouble := NewType(tyReal);
  TDouble.Name := 'Double'; TDouble.Size := 8; TDouble.RealKind := rkDouble;
  TExtended := NewType(tyReal);
  TExtended.Name := 'Extended'; TExtended.Size := 10; TExtended.RealKind := rkExtended;
  TComp := NewType(tyReal);
  TComp.Name := 'Comp'; TComp.Size := 8; TComp.RealKind := rkComp;
  TString := StringType(255);
  TString.Name := 'String';
  TText := FileType(nil);
  TText.IsText := True;
  TText.Name := 'Text';
  TPointer := PtrType(nil);
  TPointer.Name := 'Pointer';
  TNil := NewType(tyNil);
  TNil.Size := 4;
  TVoid := NewType(tyVoid);
  TUntyped := NewType(tyUntyped);
  TUntyped.Name := 'untyped';
end;

destructor TTypeStore.Destroy;
begin
  FList.Free;
  inherited Destroy;
end;

function TTypeStore.NewType(AKind: TTypeKind): TType;
begin
  Result := TType.Create(AKind);
  FList.Add(Result);
end;

function TTypeStore.IntType(const AName: string; ALo, AHi: Int64; ASize: Integer): TType;
begin
  Result := NewType(tyInt);
  Result.Name := AName;
  Result.Lo := ALo;
  Result.Hi := AHi;
  Result.Size := ASize;
end;

function SizeOfSubrange(Lo, Hi: Int64): Integer;
begin
  if (Lo >= -128) and (Hi <= 255) and ((Lo >= 0) or (Hi <= 127)) then Exit(1);
  if (Lo >= -32768) and (Hi <= 65535) and ((Lo >= 0) or (Hi <= 32767)) then Exit(2);
  Result := 4;
end;

function HostOf(T: TType): TType;
begin
  Result := T;
  while (Result <> nil) and (Result.Host <> nil) do Result := Result.Host;
end;

function TTypeStore.Subrange(AHost: TType; ALo, AHi: Int64): TType;
var
  H: TType;
begin
  H := HostOf(AHost);
  Result := NewType(H.Kind);
  Result.Host := H;
  Result.Lo := ALo;
  Result.Hi := AHi;
  if H.Kind = tyInt then Result.Size := SizeOfSubrange(ALo, AHi) else Result.Size := H.Size;
end;

function TTypeStore.StringType(AMax: Integer): TType;
begin
  Result := NewType(tyString);
  Result.MaxLen := AMax;
  Result.Size := AMax + 1;
  if AMax = 255 then Result.Name := 'String' else Result.Name := 'String[' + IntToStr(AMax) + ']';
end;

function TTypeStore.ArrayType(AIndex, AElem: TType): TType;
begin
  Result := NewType(tyArray);
  Result.Index := AIndex;
  Result.Elem := AElem;
  Result.Lo := AIndex.Lo;
  Result.Hi := AIndex.Hi;
  Result.Size := Integer(Result.Hi - Result.Lo + 1) * AElem.Size;
end;

function TTypeStore.SetType(ABase: TType): TType;
begin
  Result := NewType(tySet);
  Result.Base := ABase;
  if ABase = nil then Result.Size := 32 else Result.Size := Integer(ABase.Hi shr 3) + 1;
end;

function TTypeStore.PtrType(ABase: TType): TType;
begin
  Result := NewType(tyPtr);
  Result.Base := ABase;
  Result.Size := 4;
end;

function TTypeStore.FileType(AElem: TType): TType;
begin
  Result := NewType(tyFile);
  Result.Elem := AElem;
  Result.Size := 128;
end;

function TTypeStore.EnumType(Names: TStrings): TType;
begin
  Result := NewType(tyEnum);
  Result.EnumNames.Assign(Names);
  Result.Lo := 0;
  Result.Hi := Names.Count - 1;
  if Names.Count > 256 then Result.Size := 2 else Result.Size := 1;
end;

function TTypeStore.IntTypeFor(ALo, AHi: Int64): TType;
begin
  if (ALo >= -32768) and (AHi <= 32767) then Exit(TInteger);
  if (ALo >= 0) and (AHi <= 65535) then Exit(TWord);
  Result := TLongInt;
end;

{ ---------------- compatibility ---------------- }

function IsDescendant(A, B: TType): Boolean;
begin
  Result := False;
  while A <> nil do
  begin
    if A = B then Exit(True);
    A := A.Parent;
  end;
end;

function ProcCompat(A, B: TType): Boolean;
var
  I: Integer;
  PA, PB: TParamDesc;
begin
  if A = B then Exit(True);
  Result := False;
  if A.Params.Count <> B.Params.Count then Exit;
  for I := 0 to A.Params.Count - 1 do
  begin
    PA := TParamDesc(A.Params[I]);
    PB := TParamDesc(B.Params[I]);
    if (PA.Mode = pmVar) <> (PB.Mode = pmVar) then Exit;
    if (PA.Typ = nil) <> (PB.Typ = nil) then Exit;
    if (PA.Typ <> nil) and not SameType(PA.Typ, PB.Typ) then Exit;
  end;
  if (A.Ret = nil) <> (B.Ret = nil) then Exit;
  Result := (A.Ret = nil) or SameType(A.Ret, B.Ret);
end;

function SameType(A, B: TType): Boolean;
begin
  if A = B then Exit(True);
  Result := False;
  if (A = nil) or (B = nil) or (A.Kind <> B.Kind) then Exit;
  case A.Kind of
    tyString: Result := A.MaxLen = B.MaxLen;
    tySet: Result := (A.Base = nil) or (B.Base = nil) or (HostOf(A.Base) = HostOf(B.Base)) or
      ((A.Base.Kind <> tyEnum) and (A.Base.Kind = B.Base.Kind));
    tyPtr: Result := (A.Base = nil) or (B.Base = nil) or SameType(A.Base, B.Base);
    tyArray: Result := (A.Lo = B.Lo) and (A.Hi = B.Hi) and SameType(A.Elem, B.Elem);
    tyFile: Result := (A.IsText = B.IsText) and (((A.Elem = nil) and (B.Elem = nil)) or
      ((A.Elem <> nil) and (B.Elem <> nil) and SameType(A.Elem, B.Elem)));
    tyInt, tyBool, tyChar, tyEnum: Result := (HostOf(A) = HostOf(B)) and (A.Lo = B.Lo) and (A.Hi = B.Hi);
    tyReal: Result := A.RealKind = B.RealKind;
    tyProc: Result := ProcCompat(A, B);
  end;
end;

function Assignable(Dst, Src: TType): Boolean;
var
  DH, SH: TType;
begin
  if Dst = Src then Exit(True);
  Result := False;
  if (Dst = nil) or (Src = nil) then Exit;
  DH := HostOf(Dst);
  SH := HostOf(Src);
  case DH.Kind of
    tyInt: Result := SH.Kind = tyInt;
    tyReal: Result := SH.Kind in [tyInt, tyReal];
    tyString: Result := SH.Kind in [tyString, tyChar];
    tyEnum: Result := DH = SH;
    tyBool, tyChar: Result := DH.Kind = SH.Kind;
    tyPtr: Result := (SH.Kind = tyNil) or ((SH.Kind = tyPtr) and (SameType(DH, SH) or (DH.Base = nil) or (SH.Base = nil) or
      ((DH.Base.Kind = tyObject) and (SH.Base.Kind = tyObject) and IsDescendant(SH.Base, DH.Base))));
    tyProc: Result := (SH.Kind = tyNil) or ((SH.Kind = tyProc) and ProcCompat(DH, SH));
    tySet: Result := (SH.Kind = tySet) and SameType(DH, SH);
    tyArray: Result := (SH.Kind = tyArray) and SameType(DH, SH);
    tyRecord: Result := DH = SH;
    tyObject: Result := (SH.Kind = tyObject) and IsDescendant(SH, DH);
    tyFile: Result := DH = SH;
  end;
end;

function TypeName(T: TType): string;
begin
  if T = nil then Exit('?');
  if T.Name <> '' then Exit(T.Name);
  case T.Kind of
    tyInt, tyBool, tyChar, tyEnum: Result := 'subrange';
    tyArray: Result := 'array';
    tyRecord: Result := 'record';
    tyObject: Result := 'object';
    tySet: Result := 'set';
    tyPtr: Result := 'pointer';
    tyFile: Result := 'file';
    tyProc: Result := 'procedural type';
    tyNil: Result := 'nil';
    tyVoid: Result := 'no value';
    tyString: Result := 'string';
    tyReal: Result := 'real';
  else
    Result := 'type';
  end;
end;

end.
