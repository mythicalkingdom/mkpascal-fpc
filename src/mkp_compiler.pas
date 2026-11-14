unit mkp_compiler;
// One pass compiler: parses Pascal source and builds the executable tree (mkp_nodes) directly,
// checking types as it goes.
{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, contnrs, StrUtils, mkp_defs, mkp_lexer, mkp_types, mkp_mem, mkp_run, mkp_nodes, mkp_builtins;

type
  TSymKind = (skVar, skConst, skType, skRoutine, skBuiltin, skField, skMethod);

  TUnitSourceFunc = function(const Name: string; out Text: string): Boolean of object;

  TSymbol = class
  public
    Name: string;
    Kind: TSymKind;
    Typ: TType;
    Level, Offset: Integer;      // variables: Level 0 = global, Offset is then the address
    ByRef: Boolean;              // var parameter: the slot holds an address
    Untyped: Boolean;
    Expr: TExpr;                 // constants
    Routine: TRoutine;
    BI: TBI;
    Slot: TExpr;                 // with-field: the slot that holds the record's address
    RecType: TType;
    SelfSym: TSymbol;            // field or method seen from inside a method: the Self parameter
  end;

  TScope = class
  public
    Parent: TScope;
    Syms: TStringList;
    constructor Create(AParent: TScope);
    destructor Destroy; override;
    function Find(const AName: string): TSymbol;
    function Lookup(const AName: string): TSymbol;
  end;

  TUnitInfo = class
  public
    Name: string;
    Scope: TScope;               // the unit's interface declarations (own names)
    ExportScope: TScope;             // what clients import; nil for the builtin units (Crt, Dos ...)
    IntfDone, Done: Boolean;
  end;

  TInitBlock = record
    Addr: TAddr;
    Data: RawByteString;
  end;

  { a compiled program: everything the run time needs }
  TProgramImage = class
  public
    Types: TTypeStore;
    Pool: TObjectList;           // owns every node
    Routines: TObjectList;
    Scopes: TObjectList;
    Main: TStmt;
    GlobalEnd: TAddr;
    Inits: array of TInitBlock;
    InputAddr, OutputAddr, LstAddr, DosErrorAddr: TAddr;
    ObjTypes: TList;             // object types by VMT id - 1
    UnitInits: TList;            // initialization statements of the units, in dependency order
    Name: string;
    constructor Create;
    destructor Destroy; override;
    procedure Install(C: TRun);
  end;

  TExprArray = array of TExpr;

  TCompiler = class
  private
    FInclude: TIncludeFunc;
    FDefines: TStrings;
    FLex: TLexer;
    FImage: TProgramImage;
    FPos: Integer;
    Tok: TToken;
    FScope, FRoot: TScope;
    FRoutine: TRoutine;
    FLevel: Integer;
    FFrameTop: Integer;
    FGlobalTop, FMaxGlobals: TAddr;
    FLoopDepth: Integer;
    FPendingPtrs: array of TType;
    FPendingTok: TToken;
    FUnitSource: TUnitSourceFunc;
    FUnits: TStringList;
    FCurUnit: TUnitInfo;
    FInInterface: Boolean;
    FMethods, FForwards: TList;
    FDateTimeType, FSearchRecType: TType;
    { tokens }
    procedure Err(const Msg: string);
    procedure ErrAt(const Msg: string; const T: TToken);
    function TokDesc: string;
    procedure Next;
    function PeekTok(N: Integer): TToken;
    function IsSym(const S: string): Boolean;
    function IsKw(const K: string): Boolean;
    function IsId(const K: string): Boolean;
    function AcceptSym(const S: string): Boolean;
    function AcceptKw(const K: string): Boolean;
    procedure ExpectSym(const S: string);
    procedure ExpectKw(const K: string);
    function ExpectIdent: string;
    function SwitchOn(C: Char): Boolean;
    { symbols }
    function NewSym(const AName: string; AKind: TSymKind): TSymbol;
    procedure Declare(S: TSymbol);
    procedure PushScope;
    procedure PopScope;
    function Lookup(const AName: string): TSymbol;
    function ResolveName(const AName: string): TSymbol;
    procedure DefConst(const AName: string; AExpr: TExpr);
    procedure DefType(const AName: string; ATyp: TType);
    procedure InstallPredeclared;
    { memory }
    function AllocGlobal(Size: Integer): TAddr;
    function AllocLocal(Size: Integer): Integer;
    function TempVar(T: TType): TExpr;
    function VarAccess(S: TSymbol): TExpr;
    function FieldAccess(Sym: TSymbol): TExpr;
    { constants }
    function TryFold(E: TExpr): TExpr;
    function ConstOf(E: TExpr): TExpr;
    function ConstInt(E: TExpr): Int64;
    { types }
    function ParseTypeName: TType;
    function ParseOrdinalRange(const FirstTok: Boolean): TType;
    function ParseType: TType;
    function ParseIndexType: TType;
    function ParseRecord: TType;
    procedure ResolvePendingPtrs;
    { declarations }
    procedure ParseConstSection;
    procedure AddInit(A: TAddr; const Data: RawByteString);
    procedure ParseTypedConst(T: TType; var Buf: RawByteString; Off: Integer);
    procedure ParseTypeSection;
    procedure ParseVarSection;
    procedure ParseDecls;
    procedure ParseParams(R: TRoutine; var Off: Integer);
    procedure ParseRoutine;
    { expressions }
    function IsCharLit(E: TExpr): Boolean;
    function RValue(E: TExpr): TExpr;
    function LValueOf(E: TExpr): TExpr;
    function IsIntT(T: TType): Boolean;
    function IsNumT(T: TType): Boolean;
    function ToReal(E: TExpr): TExpr;
    function ToStr(E: TExpr): TExpr;
    function ArithType(L, R: TType): TType;
    function WrapOf(T: TType): TWrap;
    function Coerce(E: TExpr; Dst: TType; const What: string): TExpr;
    function ParseSelectors(Base: TExpr): TExpr;
    function ParseSetLiteral: TExpr;
    function ParseTypecast(T: TType): TExpr;
    function ParseCallExpr(R: TRoutine): TExpr;
    function ParseCall(R: TRoutine): TCallExpr;
    function ParseFactor: TExpr;
    function BuildNot(E: TExpr): TExpr;
    function BuildBinary(const Op: string; L, R: TExpr; const T: TToken): TExpr;
    function ParseTerm: TExpr;
    function ParseSimpleExpr: TExpr;
    function ParseExpr: TExpr;
    { predeclared routines }
    procedure ParseArgs(out Args: TExprArray);
    procedure NeedArgs(const Args: TExprArray; Min, Max: Integer; const T: TToken);
    function IntArg(E: TExpr): TExpr;
    function StrArg(E: TExpr): TExpr;
    function RealArg(E: TExpr): TExpr;
    function OrdArg(E: TExpr): TExpr;
    function FileArg(E: TExpr): TExpr;
    function TypeOfArg(E: TExpr): TType;
    function MakeFn(Id: TBI; const Args: array of TExpr; ATyp: TType): TBuiltinExpr;
    function ParseBuiltinFunc(Id: TBI; const T: TToken): TExpr;
    function MakeProc(Id: TBI; const Args: array of TExpr): TBuiltinStmt;
    procedure ParseFormatted(out E, W, D: TExpr);
    function ParseWrite(NewLine: Boolean; const T: TToken): TStmt;
    function ParseRead(NewLine: Boolean; const T: TToken): TStmt;
    function ParseBuiltinStmt(Id: TBI; const T: TToken): TStmt;
    { statements and program }
    function ParseCompound: TStmt;
    function ParseStmtList(const Stops: array of string): TStmt;
    function ParseStatement: TStmt;
    procedure ParseProgram;
    { units }
    function NewImportScope(AParent: TScope): TScope;
    procedure ImportSyms(Target, From: TScope);
    function FindUnit(const AName: string): TUnitInfo;
    function ResolveAhead(out Skip: Integer): TSymbol;
    function ResolveCurrent: TSymbol;
    function IsBuiltinUnit(const N: string): Boolean;
    procedure ParseUses;
    function UseUnit(const AName: string; const NT: TToken): TUnitInfo;
    procedure ParseUnitBody(U: TUnitInfo);
    { objects }
    function FindMethod(T: TType; const AName: string): TRoutine;
    function ParseMethodDecl(Obj: TType): TRoutine;
    function ParseObjectDecl(const AName: string): TType;
    procedure ParseCallArgs(Call: TCallExpr; First: Integer);
    function BuildMethodCall(ObjAddr: TExpr; ObjT: TType; M: TRoutine; Static, SetVmt: Boolean): TExpr;
    function ObjAddrOfMethodSym(Sym: TSymbol): TExpr;
    function ParseInherited(AsValue: Boolean): TExpr;
    procedure CheckMethodsDefined;
    function ParseNewDispose(Id: TBI; const T: TToken): TStmt;
    function ParseNewFunc(const T: TToken): TExpr;
  public
    constructor Create(AInclude: TIncludeFunc; AUnitSource: TUnitSourceFunc; ADefines: TStrings; AMaxGlobals: LongWord);
    destructor Destroy; override;
    { compile source text; raises EMKCompile }
    function Compile(const Src: string): TProgramImage;
  end;

implementation

{$I mkp_comp_a.inc}
{$I mkp_comp_b.inc}
{$I mkp_comp_c.inc}
{$I mkp_comp_d.inc}

end.
