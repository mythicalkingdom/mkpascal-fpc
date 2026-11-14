{ ===================== part A: infrastructure, types, declarations ===================== }

constructor TScope.Create(AParent: TScope);
begin
  inherited Create;
  Parent := AParent;
  Syms := TStringList.Create;
  Syms.CaseSensitive := False;
  Syms.Sorted := True;
  Syms.Duplicates := dupError;
  Syms.OwnsObjects := True;
end;

destructor TScope.Destroy;
begin
  Syms.Free;
  inherited Destroy;
end;

function TScope.Find(const AName: string): TSymbol;
var
  I: Integer;
begin
  I := Syms.IndexOf(AName);
  if I < 0 then Result := nil else Result := TSymbol(Syms.Objects[I]);
end;

function TScope.Lookup(const AName: string): TSymbol;
var
  S: TScope;
begin
  S := Self;
  while S <> nil do
  begin
    Result := S.Find(AName);
    if Result <> nil then Exit;
    S := S.Parent;
  end;
  Result := nil;
end;

{ ---------------- TProgramImage ---------------- }

constructor TProgramImage.Create;
begin
  inherited Create;
  Types := TTypeStore.Create;
  Pool := TObjectList.Create(True);
  Routines := TObjectList.Create(True);
  Scopes := TObjectList.Create(True);
  ObjTypes := TList.Create;
  UnitInits := TList.Create;
  ProcTable := TList.Create;
end;

destructor TProgramImage.Destroy;
begin
  ObjTypes.Free;
  UnitInits.Free;
  ProcTable.Free;
  Pool.Free;
  Routines.Free;
  Scopes.Free;
  Types.Free;
  inherited Destroy;
end;

procedure TProgramImage.Install(C: TRun);
var
  I: Integer;
begin
  for I := 0 to High(Inits) do
    if Length(Inits[I].Data) > 0 then
      Move(Inits[I].Data[1], C.Mem.P(Inits[I].Addr, Length(Inits[I].Data))^, Length(Inits[I].Data));
  if InputAddr <> 0 then C.SetStdFile(InputAddr, ckIn);
  if OutputAddr <> 0 then C.SetStdFile(OutputAddr, ckOut);
  if LstAddr <> 0 then C.SetStdFile(LstAddr, ckLst);
  C.ProgramName := Name;
  C.ObjTypes := ObjTypes;
  C.ProcTable := ProcTable;
  C.DosErrorAddr := DosErrorAddr;
end;

{ ---------------- tokens ---------------- }

procedure TCompiler.Err(const Msg: string);
begin
  ErrAt(Msg, Tok);
end;

procedure TCompiler.ErrAt(const Msg: string; const T: TToken);
begin
  raise EMKCompile.CreateAt(Msg, T.Line, T.Col, FLex.Files[T.FileIdx]);
end;

function TCompiler.TokDesc: string;
begin
  if Tok.Kind = tkEOF then Result := 'end of file' else Result := '''' + Tok.Text + '''';
  if Tok.Kind = tkInt then Result := IntToStr(Tok.IntVal);
end;

procedure TCompiler.Next;
begin
  if FPos < FLex.Count then Inc(FPos);
  Tok := FLex.Toks[FPos];
end;

function TCompiler.PeekTok(N: Integer): TToken;
begin
  if FPos + N <= FLex.Count then Result := FLex.Toks[FPos + N] else Result := FLex.Toks[FLex.Count];
end;

function TCompiler.IsSym(const S: string): Boolean;
begin
  Result := (Tok.Kind = tkSym) and (Tok.Key = S);
end;

function TCompiler.IsKw(const K: string): Boolean;
begin
  Result := (Tok.Kind = tkKeyword) and (Tok.Key = K);
end;

function TCompiler.IsId(const K: string): Boolean;
begin
  Result := (Tok.Kind = tkIdent) and (Tok.Key = K);
end;

function TCompiler.AcceptSym(const S: string): Boolean;
begin
  Result := IsSym(S);
  if Result then Next;
end;

function TCompiler.AcceptKw(const K: string): Boolean;
begin
  Result := IsKw(K);
  if Result then Next;
end;

procedure TCompiler.ExpectSym(const S: string);
begin
  if not IsSym(S) then Err('''' + S + ''' expected but ' + TokDesc + ' found');
  Next;
end;

procedure TCompiler.ExpectKw(const K: string);
begin
  if not IsKw(K) then Err('''' + K + ''' expected but ' + TokDesc + ' found');
  Next;
end;

function TCompiler.ExpectIdent: string;
begin
  if Tok.Kind <> tkIdent then Err('Identifier expected but ' + TokDesc + ' found');
  Result := Tok.Text;
  Next;
end;

function TCompiler.SwitchOn(C: Char): Boolean;
begin
  Result := (Tok.Sw and SwBit(C)) <> 0;
end;

{ ---------------- symbols and scopes ---------------- }

function TCompiler.NewSym(const AName: string; AKind: TSymKind): TSymbol;
begin
  Result := TSymbol.Create;
  Result.Name := AName;
  Result.Kind := AKind;
end;

procedure TCompiler.Declare(S: TSymbol);
begin
  if FScope.Find(S.Name) <> nil then Err('Duplicate identifier ''' + S.Name + '''');
  FScope.Syms.AddObject(S.Name, S);
end;

procedure TCompiler.PushScope;
begin
  FScope := TScope.Create(FScope);
  FImage.Scopes.Add(FScope);
  FScope.Syms.OwnsObjects := True;
end;

procedure TCompiler.PopScope;
begin
  FScope := FScope.Parent;
end;

function TCompiler.Lookup(const AName: string): TSymbol;
begin
  Result := FScope.Lookup(AName);
end;

procedure TCompiler.DefConst(const AName: string; AExpr: TExpr);
var
  S: TSymbol;
begin
  S := NewSym(AName, skConst);
  S.Expr := AExpr;
  S.Typ := AExpr.Typ;
  FRoot.Syms.AddObject(AName, S);
end;

procedure TCompiler.DefType(const AName: string; ATyp: TType);
var
  S: TSymbol;
begin
  S := NewSym(AName, skType);
  S.Typ := ATyp;
  FRoot.Syms.AddObject(AName, S);
end;

procedure TCompiler.InstallPredeclared;
var
  T: TTypeStore;
  I: Integer;
  Id: TBI;
  S: TSymbol;
  Colors: array[0..15] of string;
  Fld: TField;
begin
  T := FImage.Types;
  FRoot := TScope.Create(nil);
  FImage.Scopes.Add(FRoot);
  FScope := FRoot;
  DefType('Integer', T.TInteger);
  DefType('ShortInt', T.TShortInt);
  DefType('Byte', T.TByte);
  DefType('Word', T.TWord);
  DefType('LongInt', T.TLongInt);
  DefType('Real', T.TReal);
  DefType('Single', T.TSingle);
  DefType('Double', T.TDouble);
  DefType('Extended', T.TExtended);
  DefType('Comp', T.TComp);
  DefType('Boolean', T.TBoolean);
  DefType('Char', T.TChar);
  DefType('String', T.TString);
  DefType('Text', T.TText);
  DefType('Pointer', T.TPointer);
  DefConst('True', TConstInt.Create(1, T.TBoolean));
  DefConst('False', TConstInt.Create(0, T.TBoolean));
  DefConst('MaxInt', TConstInt.Create(32767, T.TInteger));
  DefConst('MaxLongInt', TConstInt.Create(2147483647, T.TLongInt));
  for I := Ord(Low(TBI)) to Ord(High(TBI)) do
  begin
    // names are looked up through BuiltinByName below
  end;
  { builtins are found by name on lookup failure, see ResolveName }
  Colors[0] := 'Black'; Colors[1] := 'Blue'; Colors[2] := 'Green'; Colors[3] := 'Cyan';
  Colors[4] := 'Red'; Colors[5] := 'Magenta'; Colors[6] := 'Brown'; Colors[7] := 'LightGray';
  Colors[8] := 'DarkGray'; Colors[9] := 'LightBlue'; Colors[10] := 'LightGreen'; Colors[11] := 'LightCyan';
  Colors[12] := 'LightRed'; Colors[13] := 'LightMagenta'; Colors[14] := 'Yellow'; Colors[15] := 'White';
  for I := 0 to 15 do DefConst(Colors[I], TConstInt.Create(I, T.TByte));
  DefConst('Blink', TConstInt.Create(128, T.TByte));
  FImage.InputAddr := AllocGlobal(128);
  FImage.OutputAddr := AllocGlobal(128);
  FImage.LstAddr := AllocGlobal(128);
  S := NewSym('Input', skVar); S.Typ := T.TText; S.Offset := FImage.InputAddr; S.Level := 0; FRoot.Syms.AddObject('Input', S);
  S := NewSym('Output', skVar); S.Typ := T.TText; S.Offset := FImage.OutputAddr; S.Level := 0; FRoot.Syms.AddObject('Output', S);
  S := NewSym('Lst', skVar); S.Typ := T.TText; S.Offset := FImage.LstAddr; S.Level := 0; FRoot.Syms.AddObject('Lst', S);
  if BuiltinByName('Abs', Id) then ;
  { Dos: types, constants and DosError }
  DefType('PathStr', T.StringType(79));
  DefType('DirStr', T.StringType(67));
  DefType('NameStr', T.StringType(8));
  DefType('ExtStr', T.StringType(4));
  FDateTimeType := T.NewType(tyRecord);
  FDateTimeType.Name := 'DateTime';
  Colors[0] := 'Year'; Colors[1] := 'Month'; Colors[2] := 'Day'; Colors[3] := 'Hour'; Colors[4] := 'Min'; Colors[5] := 'Sec';
  for I := 0 to 5 do
  begin
    Fld := TField.Create;
    Fld.Name := Colors[I];
    Fld.Typ := T.TWord;
    Fld.Offset := I * 2;
    FDateTimeType.Fields.Add(Fld);
  end;
  FDateTimeType.Size := 12;
  DefType('DateTime', FDateTimeType);
  FSearchRecType := T.NewType(tyRecord);
  FSearchRecType.Name := 'SearchRec';
  Fld := TField.Create; Fld.Name := 'Fill'; Fld.Offset := 0;
  Fld.Typ := T.ArrayType(T.Subrange(T.TLongInt, 1, 21), T.TByte);
  FSearchRecType.Fields.Add(Fld);
  Fld := TField.Create; Fld.Name := 'Attr'; Fld.Offset := 21; Fld.Typ := T.TByte; FSearchRecType.Fields.Add(Fld);
  Fld := TField.Create; Fld.Name := 'Time'; Fld.Offset := 22; Fld.Typ := T.TLongInt; FSearchRecType.Fields.Add(Fld);
  Fld := TField.Create; Fld.Name := 'Size'; Fld.Offset := 26; Fld.Typ := T.TLongInt; FSearchRecType.Fields.Add(Fld);
  Fld := TField.Create; Fld.Name := 'Name'; Fld.Offset := 30; Fld.Typ := T.StringType(12); FSearchRecType.Fields.Add(Fld);
  FSearchRecType.Size := 43;
  DefType('SearchRec', FSearchRecType);
  DefConst('ReadOnly', TConstInt.Create(1, T.TByte));
  DefConst('Hidden', TConstInt.Create(2, T.TByte));
  DefConst('SysFile', TConstInt.Create(4, T.TByte));
  DefConst('VolumeID', TConstInt.Create(8, T.TByte));
  DefConst('Directory', TConstInt.Create(16, T.TByte));
  DefConst('Archive', TConstInt.Create(32, T.TByte));
  DefConst('AnyFile', TConstInt.Create(63, T.TByte));
  FImage.DosErrorAddr := AllocGlobal(2);
  S := NewSym('DosError', skVar);
  S.Typ := T.TInteger;
  S.Offset := FImage.DosErrorAddr;
  S.Level := 0;
  FRoot.Syms.AddObject('DosError', S);
end;

{ the symbol for a name: declared symbols first, then the predeclared routines }
function TCompiler.ResolveName(const AName: string): TSymbol;
var
  Id: TBI;
begin
  Result := FScope.Lookup(AName);
  if Result <> nil then Exit;
  if BuiltinByName(AName, Id) then
  begin
    Result := NewSym(AName, skBuiltin);
    Result.BI := Id;
    FRoot.Syms.AddObject(AName, Result);
  end;
end;

{ ---------------- memory allocation ---------------- }

function TCompiler.AllocGlobal(Size: Integer): TAddr;
begin
  if FGlobalTop < 16 then FGlobalTop := 16;
  Result := FGlobalTop;
  FGlobalTop := FGlobalTop + TAddr(Size);
  if FGlobalTop and 1 <> 0 then Inc(FGlobalTop);
  if FGlobalTop > FMaxGlobals then Err('Too many global variables (data segment too large)');
end;

function TCompiler.AllocLocal(Size: Integer): Integer;
begin
  Result := FFrameTop;
  Inc(FFrameTop, Size);
  if FFrameTop and 1 <> 0 then Inc(FFrameTop);
end;

{ a scratch variable of type T in the current frame (or in globals at the main level) }
function TCompiler.TempVar(T: TType): TExpr;
begin
  if FRoutine = nil then
    Result := TGlobalAddr.Create(AllocGlobal(T.Size), T)
  else
    Result := TLocalAddr.Create(AllocLocal(T.Size), 0, T);
end;

function TCompiler.VarAccess(S: TSymbol): TExpr;
begin
  if S.Level = 0 then
    Result := TGlobalAddr.Create(TAddr(S.Offset), S.Typ)
  else if S.ByRef then
    Result := TVarParamAddr.Create(S.Offset, FLevel - S.Level, S.Typ)
  else
    Result := TLocalAddr.Create(S.Offset, FLevel - S.Level, S.Typ);
  Result.Line := Tok.Line;
end;

{ ---------------- constants ---------------- }

function TCompiler.TryFold(E: TExpr): TExpr;
var
  SS: ShortString;
  SV: TSetVal;
begin
  Result := E;
  try
    case E.Typ.ExprClass of
      ecInt: Result := TConstInt.Create(E.EvalI(nil), E.Typ);
      ecReal: Result := TConstReal.Create(E.EvalR(nil), E.Typ);
      ecStr:
        begin
          E.EvalS(nil, SS);
          Result := TConstStr.Create(SS, E.Typ);
        end;
      ecSet:
        begin
          FillChar(SV, SizeOf(SV), 0);
          E.EvalSet(nil, SV);
          Result := TConstSet.Create(SV, E.Typ);
        end;
    end;
  except
    on EMKRuntime do Result := E;
  end;
end;

function TCompiler.ConstOf(E: TExpr): TExpr;
begin
  if not E.IsConst then Err('Constant expression expected');
  Result := E;
end;

function TCompiler.ConstInt(E: TExpr): Int64;
begin
  E := ConstOf(E);
  if E.Typ.ExprClass <> ecInt then Err('Ordinal constant expected');
  Result := E.EvalI(nil);
end;

{ ---------------- types ---------------- }

function TCompiler.ParseTypeName: TType;
var
  S: TSymbol;
begin
  S := ResolveCurrent;
  if S = nil then Err('Unknown identifier ''' + Tok.Text + '''');
  if S.Kind <> skType then Err('''' + Tok.Text + ''' is not a type');
  Next;
  Result := S.Typ;
end;

function TCompiler.ParseOrdinalRange(const FirstTok: Boolean): TType;
var
  Lo, Hi: TExpr;
  A, B: Int64;
  H: TType;
begin
  Lo := RValue(ParseSimpleExpr);
  if IsCharLit(Lo) then Lo := TConstInt.Create(Ord(TConstStr(Lo).Value[1]), FImage.Types.TChar);
  ConstOf(Lo);
  ExpectSym('..');
  Hi := RValue(ParseSimpleExpr);
  if IsCharLit(Hi) then Hi := TConstInt.Create(Ord(TConstStr(Hi).Value[1]), FImage.Types.TChar);
  ConstOf(Hi);
  if (Lo.Typ.ExprClass <> ecInt) or not HostOf(Lo.Typ).IsOrdinal then Err('Ordinal type expected');
  A := Lo.EvalI(nil);
  B := Hi.EvalI(nil);
  if A > B then Err('Low bound exceeds high bound');
  H := HostOf(Lo.Typ);
  if (H.Kind = tyInt) and (H <> FImage.Types.TByte) then H := FImage.Types.TInteger;
  if H.Kind = tyInt then H := FImage.Types.TLongInt;     // integer subranges are subranges of LongInt
  Result := FImage.Types.Subrange(H, A, B);
end;

function TCompiler.ParseType: TType;
var
  T, Elem, IdxT: TType;
  Names: TStringList;
  S: TSymbol;
  N: Int64;
  Dims: array of TType;
  I, SkipN: Integer;
  Peek: TToken;
begin
  if AcceptKw('packed') then Exit(ParseType());
  if IsSym('^') then
  begin
    Next;
    if Tok.Kind <> tkIdent then Err('Type name expected');
    Result := FImage.Types.PtrType(nil);
    Result.BaseName := Tok.Text;
    S := ResolveName(Tok.Text);
    if (S <> nil) and (S.Kind = skType) then Result.Base := S.Typ
    else begin
      SetLength(FPendingPtrs, Length(FPendingPtrs) + 1);
      FPendingPtrs[High(FPendingPtrs)] := Result;
      FPendingTok := Tok;
    end;
    Next;
    Exit;
  end;
  if IsSym('(') then
  begin
    Next;
    Names := TStringList.Create;
    try
      repeat
        Names.Add(ExpectIdent);
      until not AcceptSym(',');
      ExpectSym(')');
      Result := FImage.Types.EnumType(Names);
      for I := 0 to Names.Count - 1 do
      begin
        S := NewSym(Names[I], skConst);
        S.Expr := TConstInt.Create(I, Result);
        S.Typ := Result;
        Declare(S);
      end;
    finally
      Names.Free;
    end;
    Exit;
  end;
  if AcceptKw('array') then
  begin
    ExpectSym('[');
    SetLength(Dims, 0);
    repeat
      SetLength(Dims, Length(Dims) + 1);
      Dims[High(Dims)] := ParseIndexType;
    until not AcceptSym(',');
    ExpectSym(']');
    ExpectKw('of');
    Elem := ParseType();
    for I := High(Dims) downto 0 do
    begin
      if Int64(Dims[I].Hi) - Dims[I].Lo > 16777216 then Err('Array too large');
      Elem := FImage.Types.ArrayType(Dims[I], Elem);
    end;
    Exit(Elem);
  end;
  if IsKw('record') then
  begin
    Next;
    Exit(ParseRecord);
  end;
  if AcceptKw('set') then
  begin
    ExpectKw('of');
    T := ParseType();
    if not T.IsOrdinal then Err('Set base type must be ordinal');
    if (T.Lo < 0) or (T.Hi > 255) then Err('Set base type out of range (0..255)');
    Exit(FImage.Types.SetType(T));
  end;
  if AcceptKw('file') then
  begin
    Elem := nil;
    if AcceptKw('of') then Elem := ParseType();
    Exit(FImage.Types.FileType(Elem));
  end;
  if IsKw('string') then
  begin
    Next;
    if AcceptSym('[') then
    begin
      N := ConstInt(RValue(ParseExpr));
      ExpectSym(']');
      if (N < 1) or (N > 255) then Err('String length must be 1..255');
      Exit(FImage.Types.StringType(Integer(N)));
    end;
    Exit(FImage.Types.TString);
  end;
  if IsKw('object') then Err('Object types must be declared in a type section (type T = object ... end)');
  if IsKw('procedure') or IsKw('function') then Exit(ParseProcType());
  { subrange or type name }
  if Tok.Kind = tkIdent then
  begin
    S := ResolveAhead(SkipN);
    Peek := PeekTok(SkipN + 1);
    if (S <> nil) and (S.Kind = skType) and not ((Peek.Kind = tkSym) and (Peek.Key = '..')) then
      Exit(ParseTypeName());
  end;
  Result := ParseOrdinalRange(True);
end;

function TCompiler.ParseIndexType: TType;
begin
  Result := ParseType;
  if not Result.IsOrdinal then Err('Array index must be a subrange or enumeration');
end;

function TCompiler.ParseRecord: TType;
var
  Rec: TType;
  Off: Integer;
  MaxOff, VStart: Integer;
  Names: TStringList;
  T, TagT: TType;
  F: TField;
  I: Integer;
  HaveVariant: Boolean;
  Lo, Hi: Int64;

  procedure AddFields;
  var
    Nm: TStringList;
    FT: TType;
    K: Integer;
  begin
    Nm := TStringList.Create;
    try
      while (Tok.Kind = tkIdent) do
      begin
        Nm.Clear;
        repeat
          Nm.Add(ExpectIdent);
        until not AcceptSym(',');
        ExpectSym(':');
        FT := ParseType;
        for K := 0 to Nm.Count - 1 do
        begin
          if Rec.FindField(Nm[K]) <> nil then Err('Duplicate field ''' + Nm[K] + '''');
          F := TField.Create;
          F.Name := Nm[K];
          F.Typ := FT;
          F.Offset := Off;
          Rec.Fields.Add(F);
          Inc(Off, FT.Size);
        end;
        if not AcceptSym(';') then Break;
      end;
    finally
      Nm.Free;
    end;
  end;

begin
  Rec := FImage.Types.NewType(tyRecord);
  Off := 0;
  AddFields;
  if AcceptKw('case') then
  begin
    { variant part: case [tag:] type of value: (fields); ... }
    if (Tok.Kind = tkIdent) and (PeekTok(1).Kind = tkSym) and (PeekTok(1).Key = ':') then
    begin
      Names := TStringList.Create;
      try
        Names.Add(ExpectIdent);
        ExpectSym(':');
        TagT := ParseType;
        F := TField.Create;
        F.Name := Names[0];
        F.Typ := TagT;
        F.Offset := Off;
        Rec.Fields.Add(F);
        Inc(Off, TagT.Size);
      finally
        Names.Free;
      end;
    end
    else
      TagT := ParseType;
    ExpectKw('of');
    VStart := Off;
    MaxOff := Off;
    while not IsKw('end') and not IsSym(')') do
    begin
      repeat
        ConstInt(RValue(ParseExpr));
      until not AcceptSym(',');
      ExpectSym(':');
      ExpectSym('(');
      Off := VStart;
      AddFields;
      ExpectSym(')');
      if Off > MaxOff then MaxOff := Off;
      if not AcceptSym(';') then Break;
    end;
    Off := MaxOff;
  end;
  ExpectKw('end');
  Rec.Size := Off;
  Result := Rec;
end;

procedure TCompiler.ResolvePendingPtrs;
var
  I: Integer;
  S: TSymbol;
  Keep: array of TType;
begin
  SetLength(Keep, 0);
  for I := 0 to High(FPendingPtrs) do
  begin
    S := FScope.Lookup(FPendingPtrs[I].BaseName);
    if (S <> nil) and (S.Kind = skType) then FPendingPtrs[I].Base := S.Typ
    else begin
      SetLength(Keep, Length(Keep) + 1);
      Keep[High(Keep)] := FPendingPtrs[I];
    end;
  end;
  FPendingPtrs := Keep;
end;

{ ---------------- declarations ---------------- }

procedure TCompiler.ParseConstSection;
var
  Name: string;
  T: TType;
  E: TExpr;
  S: TSymbol;
  A: TAddr;
  Buf: RawByteString;
  NameTok: TToken;
begin
  while Tok.Kind = tkIdent do
  begin
    NameTok := Tok;
    Name := ExpectIdent;
    if AcceptSym(':') then
    begin
      { typed constant: a variable with a value }
      T := ParseType;
      ExpectSym('=');
      SetLength(Buf, T.Size);
      FillChar(Buf[1], T.Size, 0);
      ParseTypedConst(T, Buf, 0);
      S := NewSym(Name, skVar);
      S.Typ := T;
      if FRoutine = nil then
      begin
        S.Level := 0;
        A := AllocGlobal(T.Size);
        S.Offset := A;
        AddInit(A, Buf);
      end
      else
      begin
        { typed constants inside routines live in global memory too }
        S.Level := 0;
        A := AllocGlobal(T.Size);
        S.Offset := A;
        AddInit(A, Buf);
      end;
      Declare(S);
    end
    else
    begin
      ExpectSym('=');
      E := RValue(ParseExpr);
      ConstOf(E);
      S := NewSym(Name, skConst);
      S.Expr := E;
      S.Typ := E.Typ;
      Declare(S);
    end;
    ExpectSym(';');
  end;
end;

procedure TCompiler.AddInit(A: TAddr; const Data: RawByteString);
begin
  SetLength(FImage.Inits, Length(FImage.Inits) + 1);
  FImage.Inits[High(FImage.Inits)].Addr := A;
  FImage.Inits[High(FImage.Inits)].Data := Data;
end;

{ the bytes of a constant of type T are written into Buf at Off }
procedure TCompiler.ParseTypedConst(T: TType; var Buf: RawByteString; Off: Integer);
var
  E: TExpr;
  I: Integer;
  Elem, F: Integer;
  S: ShortString;
  SV: TSetVal;
  Fld: TField;
  Name: string;
  R: Double;
  Count: Integer;
  Mem: TMem;
begin
  if IsSym('(') and (T.Kind in [tyArray, tyRecord]) then
  begin
    Next;
    if T.Kind = tyArray then
    begin
      Count := Integer(T.Hi - T.Lo + 1);
      for I := 0 to Count - 1 do
      begin
        ParseTypedConst(T.Elem, Buf, Off + I * T.Elem.Size);
        if I < Count - 1 then ExpectSym(',');
      end;
      AcceptSym(',');
    end
    else
    begin
      repeat
        Name := ExpectIdent;
        ExpectSym(':');
        Fld := T.FindField(Name);
        if Fld = nil then Err('Unknown field ''' + Name + '''');
        ParseTypedConst(Fld.Typ, Buf, Off + Fld.Offset);
      until not (AcceptSym(';') or AcceptSym(','));
    end;
    ExpectSym(')');
    Exit;
  end;
  E := Coerce(RValue(ParseExprFor(T)), T, 'constant');
  ConstOf(E);
  case T.ExprClass of
    ecInt:
      begin
        I := T.Size;
        case I of
          1: Buf[Off + 1] := Chr(E.EvalI(nil) and $FF);
          2: PWord(@Buf[Off + 1])^ := Word(E.EvalI(nil) and $FFFF);
          4: PLongWord(@Buf[Off + 1])^ := LongWord(E.EvalI(nil) and $FFFFFFFF);
        end;
      end;
    ecReal:
      begin
        R := E.EvalR(nil);
        Mem := TMem.Create(64);
        try
          Mem.PutReal(16, T.RealKind, R);
          Move(Mem.Data[16], Buf[Off + 1], T.Size);
        finally
          Mem.Free;
        end;
      end;
    ecStr:
      begin
        E.EvalS(nil, S);
        if Length(S) > T.MaxLen then SetLength(S, T.MaxLen);
        Buf[Off + 1] := Chr(Length(S));
        if Length(S) > 0 then Move(S[1], Buf[Off + 2], Length(S));
      end;
    ecSet:
      begin
        FillChar(SV, SizeOf(SV), 0);
        E.EvalSet(nil, SV);
        Move(SV, Buf[Off + 1], T.Size);
      end;
  else
    Err('Constant of this type is not supported');
  end;
end;

procedure TCompiler.ParseTypeSection;
var
  Name: string;
  T: TType;
  S: TSymbol;
begin
  while Tok.Kind = tkIdent do
  begin
    Name := ExpectIdent;
    ExpectSym('=');
    if IsKw('object') then
    begin
      ParseObjectDecl(Name);                  // declares the type itself
      ResolvePendingPtrs;
      ExpectSym(';');
      Continue;
    end;
    T := ParseType;
    S := NewSym(Name, skType);
    S.Typ := T;
    Declare(S);
    ResolvePendingPtrs;
    ExpectSym(';');
  end;
  if Length(FPendingPtrs) > 0 then
  begin
    FPendingPtrs := nil;
  end;
end;

procedure TCompiler.ParseVarSection;
var
  Names: TStringList;
  T: TType;
  I: Integer;
  S: TSymbol;
begin
  Names := TStringList.Create;
  try
    while Tok.Kind = tkIdent do
    begin
      Names.Clear;
      repeat
        Names.Add(ExpectIdent);
      until not AcceptSym(',');
      ExpectSym(':');
      T := ParseType;
      ResolvePendingPtrs;
      for I := 0 to Names.Count - 1 do
      begin
        S := NewSym(Names[I], skVar);
        S.Typ := T;
        S.Level := FLevel;
        if FRoutine = nil then S.Offset := AllocGlobal(T.Size) else S.Offset := AllocLocal(T.Size);
        Declare(S);
      end;
      ExpectSym(';');
    end;
  finally
    Names.Free;
  end;
end;

procedure TCompiler.ParseDecls;
begin
  while True do
  begin
    if AcceptKw('label') then
    begin
      repeat
        if Tok.Kind = tkInt then Next else ExpectIdent;
      until not AcceptSym(',');
      ExpectSym(';');
    end
    else if AcceptKw('const') then ParseConstSection
    else if AcceptKw('type') then ParseTypeSection
    else if AcceptKw('var') then ParseVarSection
    else if IsKw('procedure') or IsKw('function') then ParseRoutine
    else if IsKw('constructor') or IsKw('destructor') then ParseRoutine
    else Break;
  end;
end;

{ ---------------- routines ---------------- }

procedure TCompiler.ParseParams(R: TRoutine; var Off: Integer);
var
  Names: TStringList;
  Mode: TParamMode;
  T: TType;
  I: Integer;
  P: TParamDesc;
begin
  if not AcceptSym('(') then Exit;
  if AcceptSym(')') then Exit;
  Names := TStringList.Create;
  try
    repeat
      Mode := pmValue;
      if AcceptKw('var') then Mode := pmVar else if AcceptKw('const') then Mode := pmConst;
      Names.Clear;
      repeat
        Names.Add(ExpectIdent);
      until not AcceptSym(',');
      T := nil;
      if AcceptSym(':') then
      begin
        if IsKw('array') then
        begin
          Next;
          ExpectKw('of');
          T := FImage.Types.OpenArrayType(ParseType());
        end
        else
          T := ParseType;
      end
      else if Mode = pmValue then Err('Parameter type expected');
      for I := 0 to Names.Count - 1 do
      begin
        P := TParamDesc.Create;
        P.Name := Names[I];
        P.Typ := T;
        P.Mode := Mode;
        P.Offset := Off;
        if (T <> nil) and (T.Kind = tyOpenArray) then Inc(Off, 8)
        else if (Mode = pmVar) or (T = nil) then Inc(Off, 4)
        else Inc(Off, T.Size);
        if Off and 1 <> 0 then Inc(Off);
        R.Params.Add(P);
      end;
    until not AcceptSym(';');
    ExpectSym(')');
  finally
    Names.Free;
  end;
end;

procedure TCompiler.ParseRoutine;
var
  Kind, Name: string;
  IsFunc, Completing: Boolean;
  R: TRoutine;
  S, V, OS, SelfV, FS: TSymbol;
  Off, I, MIdx: Integer;
  SavedRoutine: TRoutine;
  SavedLevel, SavedFrameTop: Integer;
  SavedScope: TScope;
  P: TParamDesc;
  Body: TStmt;
  NameTok: TToken;
  Existing: TSymbol;
  NewParams: TRoutine;
  OwnerT, X: TType;
  F: TField;
  SavedLabels: TLabelState;
begin
  Kind := Tok.Key;
  IsFunc := Kind = 'function';
  Next;
  NameTok := Tok;
  Name := ExpectIdent;
  OwnerT := nil;
  R := nil;
  Completing := False;
  if IsSym('.') then
  begin
    { the implementation of a method: procedure TFoo.Bar(...); }
    OS := FScope.Lookup(Name);
    if (OS = nil) or (OS.Kind <> skType) or (OS.Typ.Kind <> tyObject) then ErrAt('''' + Name + ''' is not an object type', NameTok);
    OwnerT := OS.Typ;
    Next;
    NameTok := Tok;
    Name := ExpectIdent;
    MIdx := OwnerT.Methods.IndexOf(Name);
    if MIdx < 0 then ErrAt('''' + Name + ''' is not a method of ' + OwnerT.Name, NameTok);
    R := TRoutine(OwnerT.Methods.Objects[MIdx]);
    if R.Defined then ErrAt('Method ''' + OwnerT.Name + '.' + Name + ''' is already implemented', NameTok);
    Completing := True;
    if IsSym('(') then
    begin
      NewParams := TRoutine.Create;
      try
        Off := 12;
        ParseParams(NewParams, Off);
        if NewParams.Params.Count <> R.Params.Count - 1 then ErrAt('Parameters do not match the declaration of ' + OwnerT.Name + '.' + Name, NameTok);
        for I := 0 to NewParams.Params.Count - 1 do
          TParamDesc(R.Params[I + 1]).Name := TParamDesc(NewParams.Params[I]).Name;
      finally
        NewParams.Free;
      end;
    end;
    if IsFunc and AcceptSym(':') then ParseTypeName;
    ExpectSym(';');
    R.Forward := False;
  end
  else
  begin
    if (Kind = 'constructor') or (Kind = 'destructor') then ErrAt('Constructors and destructors must be methods of an object type', NameTok);
    Existing := FScope.Find(Name);
    if (Existing = nil) and (FCurUnit <> nil) and not FInInterface then Existing := FCurUnit.Scope.Find(Name);
    Completing := (Existing <> nil) and (Existing.Kind = skRoutine) and Existing.Routine.Forward and not FInInterface;
    if Completing then
    begin
      R := Existing.Routine;
      { the full definition may repeat the parameters or leave them out }
      if IsSym('(') then
      begin
        NewParams := TRoutine.Create;
        try
          Off := 8;
          ParseParams(NewParams, Off);
          if NewParams.Params.Count <> R.Params.Count then ErrAt('Parameters do not match the forward declaration', NameTok);
          for I := 0 to R.Params.Count - 1 do TParamDesc(R.Params[I]).Name := TParamDesc(NewParams.Params[I]).Name;
        finally
          NewParams.Free;
        end;
      end;
      if IsFunc and AcceptSym(':') then ParseTypeName;
      ExpectSym(';');
      R.Forward := False;
    end
    else
    begin
      R := TRoutine.Create;
      FImage.Routines.Add(R);
      R.Name := Name;
      R.Level := FLevel + 1;
      R.DeclLine := NameTok.Line;
      Off := 8;
      ParseParams(R, Off);
      if IsFunc then
      begin
        ExpectSym(':');
        R.Ret := ParseType();
        R.ResultOffset := Off;
        Inc(Off, R.Ret.Size);
        if Off and 1 <> 0 then Inc(Off);
      end;
      R.FrameSize := Off;
      ExpectSym(';');
      S := NewSym(Name, skRoutine);
      S.Routine := R;
      S.Typ := R.Ret;
      Declare(S);
    end;
  end;
  while IsId('far') or IsId('near') do
  begin
    Next;
    ExpectSym(';');
  end;
  if not Completing then
  begin
    { a declaration without a body: forward, or in a unit's interface }
    if FInInterface then
    begin
      while IsId('inline') or IsId('external') do
      begin
        Next;
        ExpectSym(';');
      end;
      R.Forward := True;
      R.Intf := True;
      FForwards.Add(R);
      Exit;
    end;
    if IsId('forward') then
    begin
      Next;
      ExpectSym(';');
      R.Forward := True;
      FForwards.Add(R);
      Exit;
    end;
  end;
  { body }
  SavedRoutine := FRoutine;
  SavedLevel := FLevel;
  SavedFrameTop := FFrameTop;
  SavedScope := FScope;
  FRoutine := R;
  FLevel := R.Level;
  BeginLabelScope(SavedLabels);
  SelfV := nil;
  if R.Owner <> nil then
  begin
    { inside a method the fields and methods of the object are in scope, on top of Self }
    SelfV := NewSym('Self', skVar);
    SelfV.Typ := R.Owner;
    SelfV.Level := FLevel;
    SelfV.Offset := 8;
    SelfV.ByRef := True;
    PushScope;
    for I := 0 to R.Owner.Fields.Count - 1 do
    begin
      F := TField(R.Owner.Fields[I]);
      FS := NewSym(F.Name, skField);
      FS.Typ := F.Typ;
      FS.Offset := F.Offset;
      FS.SelfSym := SelfV;
      FS.RecType := R.Owner;
      FScope.Syms.AddObject(F.Name, FS);
    end;
    X := R.Owner;
    while X <> nil do
    begin
      for I := 0 to X.Methods.Count - 1 do
        if FScope.Find(X.Methods[I]) = nil then
        begin
          FS := NewSym(X.Methods[I], skMethod);
          FS.Routine := TRoutine(X.Methods.Objects[I]);
          FS.SelfSym := SelfV;
          FS.RecType := R.Owner;
          FScope.Syms.AddObject(X.Methods[I], FS);
        end;
      X := X.Parent;
    end;
  end;
  PushScope;
  FFrameTop := 8;
  for I := 0 to R.Params.Count - 1 do
  begin
    P := TParamDesc(R.Params[I]);
    if (I = 0) and (SelfV <> nil) then
      V := SelfV
    else
    begin
      V := NewSym(P.Name, skVar);
      V.Typ := P.Typ;
      V.Level := FLevel;
      V.Offset := P.Offset;
      V.ByRef := ((P.Mode = pmVar) and ((P.Typ = nil) or (P.Typ.Kind <> tyOpenArray))) or (P.Typ = nil);
      V.Untyped := P.Typ = nil;
      if V.Untyped then V.Typ := FImage.Types.TUntyped;
    end;
    Declare(V);
  end;
  if R.Ret <> nil then
  begin
    V := NewSym('Result', skVar);
    V.Typ := R.Ret;
    V.Level := FLevel;
    V.Offset := R.ResultOffset;
    Declare(V);
    FFrameTop := R.ResultOffset + R.Ret.Size;
  end
  else
    FFrameTop := R.FrameSize;                 // procedures: locals start after the parameters
  if FFrameTop and 1 <> 0 then Inc(FFrameTop);
  ParseDecls;
  Body := ParseCompound;
  ExpectSym(';');
  ResolveGotos;
  EndLabelScope(SavedLabels);
  R.Body := Body;
  R.Defined := True;
  R.FrameSize := (FFrameTop + 7) and not 7;
  FScope := SavedScope;
  FRoutine := SavedRoutine;
  FLevel := SavedLevel;
  FFrameTop := SavedFrameTop;
end;
