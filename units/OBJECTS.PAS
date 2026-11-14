{ OBJECTS - the Turbo Pascal Objects unit for MKPascal.
  Left out: stream registration (Get/Put/RegisterType), TResourceFile, TStringList.
  TDosStream and TBufStream keep the file in memory and write it back on Flush and Done.
  ForEach, FirstThat and LastThat take top level routines (@Name). }
unit Objects;

interface

const
  stOk         = 0;
  stError      = -1;
  stInitError  = -2;
  stReadError  = -3;
  stWriteError = -4;
  stGetError   = -5;
  stPutError   = -6;

  stCreate    = $3C00;
  stOpenRead  = $3D00;
  stOpenWrite = $3D01;
  stOpen      = $3D02;

  coIndexError = -1;
  coOverflow   = -2;

  MaxCollectionSize = 16380;

type
  PString = ^String;
  FNameStr = string[79];
  PByteArray = ^TByteArray;
  TByteArray = array[0..16777215] of Byte;

  TPoint = record
    X, Y: Integer;
  end;

  PObject = ^TObject;
  TObject = object
    constructor Init;
    procedure Free;
    destructor Done; virtual;
  end;

  PRect = ^TRect;
  TRect = object
    A, B: TPoint;
    procedure Assign(XA, YA, XB, YB: Integer);
    procedure Copy(R: TRect);
    function Contains(P: TPoint): Boolean;
    function Equals(R: TRect): Boolean;
    function Empty: Boolean;
    procedure Grow(ADX, ADY: Integer);
    procedure Intersect(R: TRect);
    procedure Move(ADX, ADY: Integer);
    procedure Union(R: TRect);
  end;

  PStream = ^TStream;
  TStream = object(TObject)
    Status: Integer;
    ErrorInfo: Integer;
    procedure CopyFrom(var S: TStream; Count: Longint);
    procedure Error(Code, Info: Integer); virtual;
    procedure Flush; virtual;
    function GetPos: Longint; virtual;
    function GetSize: Longint; virtual;
    procedure Read(var Buf; Count: Word); virtual;
    function ReadStr: PString;
    procedure Reset;
    procedure Seek(Pos: Longint); virtual;
    function StrRead: PChar;
    procedure StrWrite(P: PChar);
    procedure Truncate; virtual;
    procedure Write(var Buf; Count: Word); virtual;
    procedure WriteStr(P: PString);
  end;

  PMemoryStream = ^TMemoryStream;
  TMemoryStream = object(TStream)
    Data: PByteArray;
    Size, Pos, Cap: Longint;
    constructor Init;
    destructor Done; virtual;
    function GetPos: Longint; virtual;
    function GetSize: Longint; virtual;
    procedure Read(var Buf; Count: Word); virtual;
    procedure Seek(NewPos: Longint); virtual;
    procedure Truncate; virtual;
    procedure Write(var Buf; Count: Word); virtual;
  end;

  PDosStream = ^TDosStream;
  TDosStream = object(TMemoryStream)
    FName: FNameStr;
    Mode: Word;
    Dirty: Boolean;
    constructor Init(FileName: FNameStr; AMode: Word);
    destructor Done; virtual;
    procedure Flush; virtual;
    procedure Write(var Buf; Count: Word); virtual;
    procedure Truncate; virtual;
  end;

  PBufStream = ^TBufStream;
  TBufStream = object(TDosStream)
    constructor Init(FileName: FNameStr; AMode, Size: Word);
  end;

  TTestFunc = function(Item: Pointer): Boolean;
  TActionProc = procedure(Item: Pointer);

  PItemList = ^TItemList;
  TItemList = array[0..MaxCollectionSize - 1] of Pointer;

  PCollection = ^TCollection;
  TCollection = object(TObject)
    Items: PItemList;
    Count: Integer;
    Limit: Integer;
    Delta: Integer;
    constructor Init(ALimit, ADelta: Integer);
    destructor Done; virtual;
    function At(Index: Integer): Pointer;
    procedure AtDelete(Index: Integer);
    procedure AtFree(Index: Integer);
    procedure AtInsert(Index: Integer; Item: Pointer);
    procedure AtPut(Index: Integer; Item: Pointer);
    procedure Delete(Item: Pointer);
    procedure DeleteAll;
    procedure Error(Code, Info: Integer); virtual;
    function FirstThat(Test: TTestFunc): Pointer;
    procedure ForEach(Action: TActionProc);
    procedure Free(Item: Pointer);
    procedure FreeAll;
    procedure FreeItem(Item: Pointer); virtual;
    function IndexOf(Item: Pointer): Integer; virtual;
    procedure Insert(Item: Pointer); virtual;
    function LastThat(Test: TTestFunc): Pointer;
    procedure Pack;
    procedure SetLimit(ALimit: Integer); virtual;
  end;

  PSortedCollection = ^TSortedCollection;
  TSortedCollection = object(TCollection)
    Duplicates: Boolean;
    constructor Init(ALimit, ADelta: Integer);
    function Compare(Key1, Key2: Pointer): Integer; virtual;
    function IndexOf(Item: Pointer): Integer; virtual;
    procedure Insert(Item: Pointer); virtual;
    function KeyOf(Item: Pointer): Pointer; virtual;
    function Search(Key: Pointer; var Index: Integer): Boolean; virtual;
  end;

  PStringCollection = ^TStringCollection;
  TStringCollection = object(TSortedCollection)
    function Compare(Key1, Key2: Pointer): Integer; virtual;
    procedure FreeItem(Item: Pointer); virtual;
  end;

  PStrCollection = ^TStrCollection;
  TStrCollection = object(TSortedCollection)
    function Compare(Key1, Key2: Pointer): Integer; virtual;
    procedure FreeItem(Item: Pointer); virtual;
  end;

procedure Abstract;
function NewStr(S: string): PString;
procedure DisposeStr(P: PString);
function LongMul(X, Y: Integer): Longint;
function LongDiv(X: Longint; Y: Integer): Integer;

implementation

procedure Abstract;
begin
  RunError(211);
end;

function NewStr(S: string): PString;
var
  P: PString;
begin
  if S = '' then NewStr := nil
  else
  begin
    GetMem(P, Length(S) + 1);
    P^ := S;
    NewStr := P;
  end;
end;

procedure DisposeStr(P: PString);
begin
  if P <> nil then FreeMem(P, Length(P^) + 1);
end;

function LongMul(X, Y: Integer): Longint;
begin
  LongMul := Longint(X) * Y;
end;

function LongDiv(X: Longint; Y: Integer): Integer;
begin
  LongDiv := X div Y;
end;

{ ---- TObject ---- }

constructor TObject.Init;
begin
end;

procedure TObject.Free;
begin
  Dispose(PObject(@Self), Done);
end;

destructor TObject.Done;
begin
end;

{ ---- TRect ---- }

procedure TRect.Assign(XA, YA, XB, YB: Integer);
begin
  A.X := XA; A.Y := YA; B.X := XB; B.Y := YB;
end;

procedure TRect.Copy(R: TRect);
begin
  A := R.A;
  B := R.B;
end;

function TRect.Contains(P: TPoint): Boolean;
begin
  Contains := (P.X >= A.X) and (P.X < B.X) and (P.Y >= A.Y) and (P.Y < B.Y);
end;

function TRect.Equals(R: TRect): Boolean;
begin
  Equals := (A.X = R.A.X) and (A.Y = R.A.Y) and (B.X = R.B.X) and (B.Y = R.B.Y);
end;

function TRect.Empty: Boolean;
begin
  Empty := (A.X >= B.X) or (A.Y >= B.Y);
end;

procedure TRect.Grow(ADX, ADY: Integer);
begin
  Dec(A.X, ADX); Dec(A.Y, ADY);
  Inc(B.X, ADX); Inc(B.Y, ADY);
end;

procedure TRect.Intersect(R: TRect);
begin
  if R.A.X > A.X then A.X := R.A.X;
  if R.A.Y > A.Y then A.Y := R.A.Y;
  if R.B.X < B.X then B.X := R.B.X;
  if R.B.Y < B.Y then B.Y := R.B.Y;
end;

procedure TRect.Move(ADX, ADY: Integer);
begin
  Inc(A.X, ADX); Inc(A.Y, ADY);
  Inc(B.X, ADX); Inc(B.Y, ADY);
end;

procedure TRect.Union(R: TRect);
begin
  if R.A.X < A.X then A.X := R.A.X;
  if R.A.Y < A.Y then A.Y := R.A.Y;
  if R.B.X > B.X then B.X := R.B.X;
  if R.B.Y > B.Y then B.Y := R.B.Y;
end;

{ ---- TStream ---- }

procedure TStream.CopyFrom(var S: TStream; Count: Longint);
var
  N: Word;
  Buffer: array[0..1023] of Byte;
begin
  while Count > 0 do
  begin
    if Count > SizeOf(Buffer) then N := SizeOf(Buffer) else N := Count;
    S.Read(Buffer, N);
    Write(Buffer, N);
    Dec(Count, N);
  end;
end;

procedure TStream.Error(Code, Info: Integer);
begin
  Status := Code;
  ErrorInfo := Info;
end;

procedure TStream.Flush;
begin
end;

function TStream.GetPos: Longint;
begin
  Abstract;
  GetPos := 0;
end;

function TStream.GetSize: Longint;
begin
  Abstract;
  GetSize := 0;
end;

procedure TStream.Read(var Buf; Count: Word);
begin
  Abstract;
end;

function TStream.ReadStr: PString;
var
  L: Byte;
  P: PString;
begin
  Read(L, 1);
  if L > 0 then
  begin
    GetMem(P, L + 1);
    P^[0] := Chr(L);
    Read(P^[1], L);
    ReadStr := P;
  end
  else ReadStr := nil;
end;

procedure TStream.Reset;
begin
  Status := stOk;
  ErrorInfo := 0;
end;

procedure TStream.Seek(Pos: Longint);
begin
  Abstract;
end;

function TStream.StrRead: PChar;
var
  L: Word;
  P: PChar;
begin
  Read(L, SizeOf(Word));
  if L = 0 then StrRead := nil
  else
  begin
    GetMem(P, L + 1);
    Read(P^, L);
    P[L] := #0;
    StrRead := P;
  end;
end;

procedure TStream.StrWrite(P: PChar);
var
  L: Word;
begin
  if P = nil then L := 0 else L := StrLen(P);
  Write(L, SizeOf(Word));
  if P <> nil then Write(P^, L);
end;

procedure TStream.Truncate;
begin
  Abstract;
end;

procedure TStream.Write(var Buf; Count: Word);
begin
  Abstract;
end;

procedure TStream.WriteStr(P: PString);
const
  Empty: Byte = 0;
begin
  if P <> nil then Write(P^, Length(P^) + 1)
  else Write(Empty, 1);
end;

{ ---- TMemoryStream ---- }

procedure GrowData(var Data: PByteArray; var Cap: Longint; Need: Longint);
var
  NewCap: Longint;
  P: PByteArray;
begin
  if Need <= Cap then Exit;
  NewCap := Cap * 2;
  if NewCap < Need then NewCap := Need;
  if NewCap < 256 then NewCap := 256;
  GetMem(P, NewCap);
  FillChar(P^, NewCap, 0);
  if Data <> nil then
  begin
    Move(Data^, P^, Cap);
    FreeMem(Data, Cap);
  end;
  Data := P;
  Cap := NewCap;
end;

constructor TMemoryStream.Init;
begin
  TStream.Init;
  Status := stOk;
  ErrorInfo := 0;
  Data := nil;
  Size := 0;
  Pos := 0;
  Cap := 0;
end;

destructor TMemoryStream.Done;
begin
  if Data <> nil then FreeMem(Data, Cap);
  Data := nil;
  Cap := 0;
  TStream.Done;
end;

function TMemoryStream.GetPos: Longint;
begin
  if Status <> stOk then GetPos := -1 else GetPos := Pos;
end;

function TMemoryStream.GetSize: Longint;
begin
  if Status <> stOk then GetSize := -1 else GetSize := Size;
end;

procedure TMemoryStream.Read(var Buf; Count: Word);
var
  N: Longint;
begin
  if Status <> stOk then
  begin
    FillChar(Buf, Count, 0);
    Exit;
  end;
  N := Size - Pos;
  if N < 0 then N := 0;
  if N > Count then N := Count;
  if N > 0 then Move(Data^[Pos], Buf, N);
  if N < Count then
  begin
    FillChar(Buf, Count, 0);
    if N > 0 then Move(Data^[Pos], Buf, N);
    Error(stReadError, 0);
  end;
  Inc(Pos, N);
end;

procedure TMemoryStream.Seek(NewPos: Longint);
begin
  if Status <> stOk then Exit;
  if NewPos < 0 then NewPos := 0;
  Pos := NewPos;
end;

procedure TMemoryStream.Truncate;
begin
  if Status <> stOk then Exit;
  if Pos < Size then Size := Pos;
end;

procedure TMemoryStream.Write(var Buf; Count: Word);
begin
  if Status <> stOk then Exit;
  if Count = 0 then Exit;
  GrowData(Data, Cap, Pos + Count);
  Move(Buf, Data^[Pos], Count);
  Inc(Pos, Count);
  if Pos > Size then Size := Pos;
end;

{ ---- TDosStream and TBufStream: the file lives in memory ---- }

procedure LoadFileData(const Name: FNameStr; var Data: PByteArray; var Cap, Size: Longint; var Ok: Boolean);
var
  F: file;
  N: Longint;
begin
  Ok := False;
  Size := 0;
  Cap := 0;
  Data := nil;
  Assign(F, Name);
  {$I-}
  Reset(F, 1);
  {$I+}
  if IOResult <> 0 then Exit;
  N := FileSize(F);
  if N > 0 then
  begin
    GrowData(Data, Cap, N);
    BlockRead(F, Data^, N);
  end;
  Close(F);
  Size := N;
  Ok := True;
end;

procedure SaveFileData(const Name: FNameStr; Data: PByteArray; Size: Longint; var Ok: Boolean);
var
  F: file;
begin
  Ok := False;
  Assign(F, Name);
  {$I-}
  Rewrite(F, 1);
  {$I+}
  if IOResult <> 0 then Exit;
  if Size > 0 then BlockWrite(F, Data^, Size);
  Close(F);
  Ok := True;
end;

constructor TDosStream.Init(FileName: FNameStr; AMode: Word);
var
  Ok: Boolean;
begin
  TMemoryStream.Init;
  FName := FileName;
  Mode := AMode;
  Dirty := False;
  if AMode = stCreate then
  begin
    SaveFileData(FName, nil, 0, Ok);
    if not Ok then Error(stInitError, 2);
  end
  else
  begin
    LoadFileData(FName, Data, Cap, Size, Ok);
    if not Ok then Error(stInitError, 2);
  end;
end;

procedure TDosStream.Flush;
var
  Ok: Boolean;
begin
  if Dirty and (Mode <> stOpenRead) and (Status = stOk) then
  begin
    SaveFileData(FName, Data, Size, Ok);
    if not Ok then Error(stWriteError, 0);
    Dirty := False;
  end;
end;

destructor TDosStream.Done;
begin
  Flush;
  TMemoryStream.Done;
end;

procedure TDosStream.Write(var Buf; Count: Word);
begin
  if Mode = stOpenRead then
  begin
    Error(stWriteError, 5);
    Exit;
  end;
  TMemoryStream.Write(Buf, Count);
  Dirty := True;
end;

procedure TDosStream.Truncate;
begin
  TMemoryStream.Truncate;
  Dirty := True;
end;

constructor TBufStream.Init(FileName: FNameStr; AMode, Size: Word);
begin
  TDosStream.Init(FileName, AMode);
end;

{ ---- TCollection ---- }

constructor TCollection.Init(ALimit, ADelta: Integer);
begin
  TObject.Init;
  Items := nil;
  Count := 0;
  Limit := 0;
  Delta := ADelta;
  SetLimit(ALimit);
end;

destructor TCollection.Done;
begin
  FreeAll;
  SetLimit(0);
end;

function TCollection.At(Index: Integer): Pointer;
begin
  if (Index < 0) or (Index >= Count) then
  begin
    Error(coIndexError, Index);
    At := nil;
  end
  else At := Items^[Index];
end;

procedure TCollection.AtDelete(Index: Integer);
var
  I: Integer;
begin
  if (Index < 0) or (Index >= Count) then Error(coIndexError, Index)
  else
  begin
    for I := Index to Count - 2 do Items^[I] := Items^[I + 1];
    Dec(Count);
  end;
end;

procedure TCollection.AtFree(Index: Integer);
var
  Item: Pointer;
begin
  Item := At(Index);
  AtDelete(Index);
  FreeItem(Item);
end;

procedure TCollection.AtInsert(Index: Integer; Item: Pointer);
var
  I: Integer;
begin
  if (Index < 0) or (Index > Count) then Error(coIndexError, Index)
  else
  begin
    if Count = Limit then SetLimit(Limit + Delta);
    if Count = Limit then Error(coOverflow, Index)
    else
    begin
      for I := Count - 1 downto Index do Items^[I + 1] := Items^[I];
      Items^[Index] := Item;
      Inc(Count);
    end;
  end;
end;

procedure TCollection.AtPut(Index: Integer; Item: Pointer);
begin
  if (Index < 0) or (Index >= Count) then Error(coIndexError, Index)
  else Items^[Index] := Item;
end;

procedure TCollection.Delete(Item: Pointer);
begin
  AtDelete(IndexOf(Item));
end;

procedure TCollection.DeleteAll;
begin
  Count := 0;
end;

procedure TCollection.Error(Code, Info: Integer);
begin
  RunError(212 - Code);
end;

function TCollection.FirstThat(Test: TTestFunc): Pointer;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    if Test(Items^[I]) then
    begin
      FirstThat := Items^[I];
      Exit;
    end;
  FirstThat := nil;
end;

procedure TCollection.ForEach(Action: TActionProc);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do Action(Items^[I]);
end;

procedure TCollection.Free(Item: Pointer);
begin
  Delete(Item);
  FreeItem(Item);
end;

procedure TCollection.FreeAll;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do FreeItem(Items^[I]);
  Count := 0;
end;

procedure TCollection.FreeItem(Item: Pointer);
begin
  if Item <> nil then Dispose(PObject(Item), Done);
end;

function TCollection.IndexOf(Item: Pointer): Integer;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    if Items^[I] = Item then
    begin
      IndexOf := I;
      Exit;
    end;
  IndexOf := -1;
end;

procedure TCollection.Insert(Item: Pointer);
begin
  AtInsert(Count, Item);
end;

function TCollection.LastThat(Test: TTestFunc): Pointer;
var
  I: Integer;
begin
  for I := Count - 1 downto 0 do
    if Test(Items^[I]) then
    begin
      LastThat := Items^[I];
      Exit;
    end;
  LastThat := nil;
end;

procedure TCollection.Pack;
var
  I, J: Integer;
begin
  J := 0;
  for I := 0 to Count - 1 do
    if Items^[I] <> nil then
    begin
      Items^[J] := Items^[I];
      Inc(J);
    end;
  Count := J;
end;

procedure TCollection.SetLimit(ALimit: Integer);
var
  NewItems: PItemList;
begin
  if ALimit < Count then ALimit := Count;
  if ALimit > MaxCollectionSize then ALimit := MaxCollectionSize;
  if ALimit <> Limit then
  begin
    if ALimit = 0 then NewItems := nil
    else
    begin
      GetMem(NewItems, ALimit * SizeOf(Pointer));
      if (Count <> 0) and (Items <> nil) then Move(Items^, NewItems^, Count * SizeOf(Pointer));
    end;
    if Limit <> 0 then FreeMem(Items, Limit * SizeOf(Pointer));
    Items := NewItems;
    Limit := ALimit;
  end;
end;

{ ---- TSortedCollection ---- }

constructor TSortedCollection.Init(ALimit, ADelta: Integer);
begin
  TCollection.Init(ALimit, ADelta);
  Duplicates := False;
end;

function TSortedCollection.Compare(Key1, Key2: Pointer): Integer;
begin
  Abstract;
  Compare := 0;
end;

function TSortedCollection.IndexOf(Item: Pointer): Integer;
var
  I: Integer;
begin
  IndexOf := -1;
  if Search(KeyOf(Item), I) then
  begin
    if Duplicates then
      while (I < Count) and (Item <> Items^[I]) do Inc(I);
    if I < Count then IndexOf := I;
  end;
end;

procedure TSortedCollection.Insert(Item: Pointer);
var
  I: Integer;
begin
  if not Search(KeyOf(Item), I) or Duplicates then AtInsert(I, Item);
end;

function TSortedCollection.KeyOf(Item: Pointer): Pointer;
begin
  KeyOf := Item;
end;

function TSortedCollection.Search(Key: Pointer; var Index: Integer): Boolean;
var
  L, H, I, C: Integer;
begin
  Search := False;
  L := 0;
  H := Count - 1;
  while L <= H do
  begin
    I := (L + H) shr 1;
    C := Compare(KeyOf(Items^[I]), Key);
    if C < 0 then L := I + 1
    else
    begin
      H := I - 1;
      if C = 0 then
      begin
        Search := True;
        if not Duplicates then L := I;
      end;
    end;
  end;
  Index := L;
end;

{ ---- string collections ---- }

function TStringCollection.Compare(Key1, Key2: Pointer): Integer;
var
  A, B: PString;
begin
  A := PString(Key1);
  B := PString(Key2);
  if A^ < B^ then Compare := -1
  else if A^ > B^ then Compare := 1
  else Compare := 0;
end;

procedure TStringCollection.FreeItem(Item: Pointer);
begin
  DisposeStr(PString(Item));
end;

function TStrCollection.Compare(Key1, Key2: Pointer): Integer;
begin
  Compare := StrComp(PChar(Key1), PChar(Key2));
end;

procedure TStrCollection.FreeItem(Item: Pointer);
begin
  StrDispose(PChar(Item));
end;

end.
