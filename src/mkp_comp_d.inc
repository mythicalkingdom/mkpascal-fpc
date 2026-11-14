{ ===================== part D: units and objects ===================== }

{ ---------------- units ---------------- }

function TCompiler.NewImportScope(AParent: TScope): TScope;
begin
  Result := TScope.Create(AParent);
  Result.Syms.OwnsObjects := False;          // the symbols belong to the unit that exports them
  FImage.Scopes.Add(Result);
end;

procedure TCompiler.ImportSyms(Target, From: TScope);
var
  I, J: Integer;
begin
  for I := 0 to From.Syms.Count - 1 do
  begin
    J := Target.Syms.IndexOf(From.Syms[I]);
    if J >= 0 then Target.Syms.Delete(J);     // a later unit in the uses list shadows an earlier one
    Target.Syms.AddObject(From.Syms[I], From.Syms.Objects[I]);
  end;
end;

function TCompiler.FindUnit(const AName: string): TUnitInfo;
var
  I: Integer;
begin
  I := FUnits.IndexOf(AName);
  if I < 0 then Result := nil else Result := TUnitInfo(FUnits.Objects[I]);
end;

{ the symbol named by the identifier at the current token, which may be Unit.Name; Skip counts the tokens
  (the unit name and the dot) that come before the identifier itself }
function TCompiler.ResolveAhead(out Skip: Integer): TSymbol;
var
  U: TUnitInfo;
  Local: TSymbol;
  Mem: TToken;
begin
  Skip := 0;
  if (Tok.Kind = tkIdent) and (PeekTok(1).Kind = tkSym) and (PeekTok(1).Key = '.') and (PeekTok(2).Kind = tkIdent) then
  begin
    U := FindUnit(Tok.Text);
    if U <> nil then
    begin
      Local := FScope.Lookup(Tok.Text);
      if (Local = nil) or not (Local.Kind in [skVar, skField]) then
      begin
        Skip := 2;
        Mem := PeekTok(2);
        if U.ExportScope = nil then Result := ResolveName(Mem.Text)
        else Result := U.ExportScope.Find(Mem.Text);
        if Result = nil then ErrAt('Unknown identifier ''' + U.Name + '.' + Mem.Text + '''', Mem);
        Exit;
      end;
    end;
  end;
  Result := ResolveName(Tok.Text);
end;

function TCompiler.ResolveCurrent: TSymbol;
var
  Skip: Integer;
begin
  Result := ResolveAhead(Skip);
  while Skip > 0 do
  begin
    Next;
    Dec(Skip);
  end;
end;

function TCompiler.IsBuiltinUnit(const N: string): Boolean;
begin
  Result := SameText(N, 'Crt') or SameText(N, 'Dos') or SameText(N, 'Printer') or SameText(N, 'System') or
            SameText(N, 'Strings');
end;

procedure TCompiler.ParseUses;
var
  Nm: string;
  NT: TToken;
  U: TUnitInfo;
begin
  while AcceptKw('uses') do
  begin
    repeat
      NT := Tok;
      Nm := ExpectIdent;
      if IsBuiltinUnit(Nm) then
      begin
        if FindUnit(Nm) = nil then
        begin
          U := TUnitInfo.Create;
          U.Name := Nm;
          U.IntfDone := True;
          U.Done := True;
          FUnits.AddObject(Nm, U);
        end;
      end
      else
      begin
        U := UseUnit(Nm, NT);
        ImportSyms(FScope, U.ExportScope);
      end;
    until not AcceptSym(',');
    ExpectSym(';');
  end;
end;

{ compile a unit (once) and return its record }
function TCompiler.UseUnit(const AName: string; const NT: TToken): TUnitInfo;
var
  U: TUnitInfo;
  Text: string;
  SLex: TLexer;
  SPos, SFrameTop, SLoop, SLevel: Integer;
  STok: TToken;
  SScope: TScope;
  SRoutine: TRoutine;
  SUnit: TUnitInfo;
  SIntf: Boolean;
begin
  U := FindUnit(AName);
  if U <> nil then
  begin
    if not U.IntfDone then ErrAt('Circular unit reference: ' + AName, NT);
    Exit(U);
  end;
  if not Assigned(FUnitSource) or not FUnitSource(AName, Text) then ErrAt('Unit file not found: ' + AName, NT);
  U := TUnitInfo.Create;
  U.Name := AName;
  FUnits.AddObject(AName, U);
  SLex := FLex; SPos := FPos; STok := Tok; SScope := FScope; SRoutine := FRoutine; SLevel := FLevel;
  SFrameTop := FFrameTop; SLoop := FLoopDepth; SUnit := FCurUnit; SIntf := FInInterface;
  FLex := TLexer.Create(FInclude, FDefines);
  try
    try
      FLex.Tokenize(Text);
      FPos := 0;
      Tok := FLex.Toks[0];
      FRoutine := nil;
      FLevel := 0;
      FLoopDepth := 0;
      ParseUnitBody(U);
    except
      on E: EMKCompile do
      begin
        if E.InUnit = '' then E.InUnit := AName;
        raise;
      end;
    end;
  finally
    FLex.Free;
    FLex := SLex; FPos := SPos; Tok := STok; FScope := SScope; FRoutine := SRoutine; FLevel := SLevel;
    FFrameTop := SFrameTop; FLoopDepth := SLoop; FCurUnit := SUnit; FInInterface := SIntf;
  end;
  Result := U;
end;

procedure TCompiler.ParseUnitBody(U: TUnitInfo);
var
  IntfImports, ImplImports, ImplScope: TScope;
  Init: TStmt;
  MStart, FStart, I: Integer;
  S: TSymbol;
  NT: TToken;
  SavedLabels: TLabelState;
begin
  MStart := FMethods.Count;
  FStart := FForwards.Count;
  NT := Tok;
  ExpectKw('unit');
  if not SameText(Tok.Text, U.Name) then Err('File for unit ''' + U.Name + ''' does not contain that unit');
  ExpectIdent;
  ExpectSym(';');
  ExpectKw('interface');
  IntfImports := NewImportScope(FRoot);
  FScope := IntfImports;
  ParseUses;
  U.Scope := TScope.Create(IntfImports);
  FImage.Scopes.Add(U.Scope);
  FScope := U.Scope;
  FCurUnit := U;
  FInInterface := True;
  ParseDecls;
  ExpectKw('implementation');
  FInInterface := False;
  U.ExportScope := U.Scope;
  U.IntfDone := True;
  { the implementation sees the interface plus what its own uses clause imports; its own names win }
  ImplImports := NewImportScope(IntfImports);
  U.Scope.Parent := ImplImports;
  FScope := ImplImports;
  ParseUses;
  ImplScope := TScope.Create(U.Scope);
  FImage.Scopes.Add(ImplScope);
  FScope := ImplScope;
  ParseDecls;
  Init := nil;
  BeginLabelScope(SavedLabels);
  if AcceptKw('begin') then
    Init := ParseStmtList(['end'])
  else if IsId('initialization') then
  begin
    Next;
    Init := ParseStmtList(['end']);
  end;
  ResolveGotos;
  EndLabelScope(SavedLabels);
  ExpectKw('end');
  ExpectSym('.');
  for I := FStart to FForwards.Count - 1 do
    if TRoutine(FForwards[I]).Forward then
      raise EMKCompile.CreateAt('Routine ''' + TRoutine(FForwards[I]).Name + ''' is declared in the ' +
        'interface (or forward) but has no implementation', TRoutine(FForwards[I]).DeclLine, 1, FLex.Files[0]);
  for I := MStart to FMethods.Count - 1 do
    if not TRoutine(FMethods[I]).Defined then
      raise EMKCompile.CreateAt('Method ''' + TRoutine(FMethods[I]).Owner.Name + '.' + TRoutine(FMethods[I]).Name +
        ''' has no implementation', TRoutine(FMethods[I]).DeclLine, 1, FLex.Files[0]);
  if (Init <> nil) and (TCompound(Init).Items <> nil) then FImage.UnitInits.Add(Init);
  U.Done := True;
  S := nil;
  if S <> nil then ;
end;

{ ---------------- objects ---------------- }

function TCompiler.FindMethod(T: TType; const AName: string): TRoutine;
var
  I: Integer;
  X: TType;
begin
  X := T;
  while X <> nil do
  begin
    if X.Kind <> tyObject then Break;
    I := X.Methods.IndexOf(AName);
    if I >= 0 then Exit(TRoutine(X.Methods.Objects[I]));
    X := X.Parent;
  end;
  Result := nil;
end;

function TCompiler.ParseMethodDecl(Obj: TType): TRoutine;
var
  Kind, Name: string;
  NameTok: TToken;
  R, Ex: TRoutine;
  P: TParamDesc;
  Off: Integer;
  VirtDecl: Boolean;
begin
  Kind := Tok.Key;
  Next;
  NameTok := Tok;
  Name := ExpectIdent;
  if (Obj.FindField(Name) <> nil) or (Obj.Methods.IndexOf(Name) >= 0) then ErrAt('Duplicate identifier ''' + Name + '''', NameTok);
  R := TRoutine.Create;
  FImage.Routines.Add(R);
  R.Name := Name;
  R.Owner := Obj;
  R.Level := FLevel + 1;
  R.DeclLine := NameTok.Line;
  R.IsCtor := Kind = 'constructor';
  R.IsDtor := Kind = 'destructor';
  P := TParamDesc.Create;
  P.Name := 'Self';
  P.Typ := Obj;
  P.Mode := pmVar;
  P.Offset := 8;
  R.Params.Add(P);
  Off := 12;
  ParseParams(R, Off);
  if Kind = 'function' then
  begin
    ExpectSym(':');
    R.Ret := ParseType();
    R.ResultOffset := Off;
    Inc(Off, R.Ret.Size);
    if Off and 1 <> 0 then Inc(Off);
  end;
  R.FrameSize := Off;
  ExpectSym(';');
  VirtDecl := False;
  while IsId('virtual') or IsId('override') or IsId('far') or IsId('near') do
  begin
    if IsId('virtual') or IsId('override') then VirtDecl := True;
    Next;
    ExpectSym(';');
  end;
  Ex := nil;
  if Obj.Parent <> nil then Ex := FindMethod(Obj.Parent, Name);
  if (Ex <> nil) and Ex.IsVirtual then
  begin
    R.IsVirtual := True;
    R.VIndex := Ex.VIndex;
    Obj.Vtab[R.VIndex] := R;
  end
  else if VirtDecl then
  begin
    R.IsVirtual := True;
    R.VIndex := Obj.Vtab.Count;
    Obj.Vtab.Add(R);
  end;
  if R.IsCtor and R.IsVirtual then ErrAt('A constructor cannot be virtual', NameTok);
  Obj.Methods.AddObject(Name, R);
  FMethods.Add(R);
  Result := R;
end;

function TCompiler.ParseObjectDecl(const AName: string): TType;
var
  Obj, Par, FT: TType;
  S, PS: TSymbol;
  Off, I, K: Integer;
  F, PF: TField;
  Names: TStringList;
  HasVirt: Boolean;
  M: TRoutine;
  FieldTok: TToken;
begin
  ExpectKw('object');
  Obj := FImage.Types.NewType(tyObject);
  Obj.Name := AName;
  S := NewSym(AName, skType);
  S.Typ := Obj;
  Declare(S);                                   // before the members, so they can refer to the type itself
  Obj.VmtId := FImage.ObjTypes.Add(Obj) + 1;
  Off := 0;
  if AcceptSym('(') then
  begin
    PS := ResolveCurrent;
    if (PS = nil) or (PS.Kind <> skType) or (PS.Typ.Kind <> tyObject) then Err('Object type expected');
    Next;
    Par := PS.Typ;
    ExpectSym(')');
    Obj.Parent := Par;
    for I := 0 to Par.Fields.Count - 1 do
    begin
      PF := TField(Par.Fields[I]);
      F := TField.Create;
      F.Name := PF.Name;
      F.Typ := PF.Typ;
      F.Offset := PF.Offset;
      Obj.Fields.Add(F);
    end;
    for I := 0 to Par.Vtab.Count - 1 do Obj.Vtab.Add(Par.Vtab[I]);
    Obj.VmtOff := Par.VmtOff;
    Off := Par.Size;
  end;
  HasVirt := False;
  Names := TStringList.Create;
  try
    while not IsKw('end') do
    begin
      if (IsId('private') or IsId('public') or IsId('protected')) and
         not ((PeekTok(1).Kind = tkSym) and ((PeekTok(1).Key = ':') or (PeekTok(1).Key = ','))) then
      begin
        Next;
        Continue;
      end;
      if IsKw('procedure') or IsKw('function') or IsKw('constructor') or IsKw('destructor') then
      begin
        M := ParseMethodDecl(Obj);
        if M.IsVirtual then HasVirt := True;
      end
      else if Tok.Kind = tkIdent then
      begin
        Names.Clear;
        FieldTok := Tok;
        repeat
          Names.Add(ExpectIdent);
        until not AcceptSym(',');
        ExpectSym(':');
        FT := ParseType();
        for K := 0 to Names.Count - 1 do
        begin
          if (Obj.FindField(Names[K]) <> nil) or (Obj.Methods.IndexOf(Names[K]) >= 0) then
            ErrAt('Duplicate identifier ''' + Names[K] + '''', FieldTok);
          F := TField.Create;
          F.Name := Names[K];
          F.Typ := FT;
          F.Offset := Off;
          Obj.Fields.Add(F);
          Inc(Off, FT.Size);
        end;
        if not AcceptSym(';') and not IsKw('end') then ExpectSym(';');
      end
      else
        Err('Field or method declaration expected but ' + TokDesc + ' found');
    end;
  finally
    Names.Free;
  end;
  ExpectKw('end');
  if (Obj.VmtOff < 0) and HasVirt then
  begin
    Obj.VmtOff := Off;                          // the VMT pointer follows the fields of the type that introduces virtual methods
    Inc(Off, 2);
  end;
  Obj.Size := Off;
  Result := Obj;
end;

procedure TCompiler.ParseCallArgs(Call: TCallExpr; First: Integer);
var
  R: TRoutine;
  I: Integer;
  P: TParamDesc;
  A: TArg;
  E, L: TExpr;
  AT: TType;
begin
  R := Call.Routine;
  if R.Params.Count > First then
  begin
    if not IsSym('(') then Err('Not enough actual parameters');
    Next;
    for I := First to R.Params.Count - 1 do
    begin
      if I > First then
      begin
        if not IsSym(',') then Err('Not enough actual parameters');
        Next;
      end;
      P := TParamDesc(R.Params[I]);
      A := TArg.Create;
      A.Mode := P.Mode;
      A.Typ := P.Typ;
      A.Offset := P.Offset;
      if (P.Typ <> nil) and (P.Typ.Kind = tyOpenArray) then
      begin
        E := ParseExpr;
        AT := HostOf(E.Typ);
        if not (AT.Kind in [tyArray, tyOpenArray]) then Err('Array expected for the open array parameter ''' + P.Name + '''');
        if not SameType(P.Typ.Elem, AT.Elem) then Err('The array''s element type does not match the parameter ''' + P.Name + '''');
        if (P.Mode <> pmValue) and not E.IsLValue then Err('Variable expected');
        A.IsOpen := True;
        A.FromOpen := AT.Kind = tyOpenArray;
        A.ElemSize := P.Typ.Elem.Size;
        if AT.Kind = tyArray then A.ActCount := AT.Hi - AT.Lo + 1;
        A.Expr := E;
        Call.Args.Add(A);
        Continue;
      end;
      if (P.Mode = pmVar) or (P.Typ = nil) then E := ParseExpr else E := ParseExprFor(P.Typ);
      if (P.Mode = pmVar) or (P.Typ = nil) then
      begin
        if (P.Typ = nil) and (P.Mode = pmConst) and not E.IsLValue and not IsLoadNode(E) then
          Err('Variable expected');
        L := LValueOf(E);
        if (P.Typ <> nil) and not SameType(P.Typ, L.Typ) and
           not ((P.Typ.Kind = tyObject) and (L.Typ.Kind = tyObject) and IsDescendant(L.Typ, P.Typ)) then
          Err('Types of actual and formal var parameters must be identical');
        A.Expr := L;
      end
      else
        A.Expr := Coerce(E, P.Typ, ' in parameter ''' + P.Name + '''');
      Call.Args.Add(A);
    end;
    if IsSym(',') then Err('Too many actual parameters');
    ExpectSym(')');
  end
  else if IsSym('(') then
  begin
    Next;
    if not IsSym(')') then Err('Too many actual parameters');
    Next;
  end;
end;

{ a call of method M on the object whose address ObjAddr evaluates to }
function TCompiler.BuildMethodCall(ObjAddr: TExpr; ObjT: TType; M: TRoutine; Static, SetVmt: Boolean): TExpr;
var
  Call: TCallExpr;
  A: TArg;
begin
  Call := TCallExpr.Create(M, FLevel);
  Call.Line := Tok.Line;
  Call.SelfExpr := ObjAddr;
  Call.VmtOff := ObjT.VmtOff;
  A := TArg.Create;
  A.Mode := pmVar;
  A.Typ := nil;
  A.Offset := 8;
  A.Expr := ObjAddr;
  Call.Args.Add(A);
  if (not Static) and M.IsVirtual then Call.VirtIndex := M.VIndex;
  if SetVmt and M.IsCtor and (ObjT.VmtOff >= 0) then Call.SetVmtId := ObjT.VmtId;
  if M.IsCtor then
  begin
    Call.IsCtor := True;
    Call.Typ := FImage.Types.TBoolean;
  end
  else if M.Ret = nil then
    Call.Typ := FImage.Types.TVoid;
  ParseCallArgs(Call, 1);
  if (M.Ret <> nil) and (M.Ret.ExprClass = ecMem) then Call.TempAddr := TempVar(M.Ret);
  Result := Call;
end;

function TCompiler.ObjAddrOfMethodSym(Sym: TSymbol): TExpr;
begin
  if Sym.SelfSym <> nil then Result := VarAccess(Sym.SelfSym)
  else Result := TDerefAddr.Create(TLoad.Create(Sym.Slot, FImage.Types.TPointer), Sym.RecType);
end;

{ inherited [Name(args)] inside a method: a static call of the ancestor's method on Self }
function TCompiler.ParseInherited(AsValue: Boolean): TExpr;
var
  Name: string;
  NT: TToken;
  M: TRoutine;
  SelfSym: TSymbol;
begin
  if (FRoutine = nil) or (FRoutine.Owner = nil) then Err('''inherited'' can only be used inside a method');
  Next;
  NT := Tok;
  if Tok.Kind = tkIdent then
  begin
    Name := Tok.Text;
    Next;
  end
  else
  begin
    if AsValue then Err('Method name expected after ''inherited''');
    Name := FRoutine.Name;
  end;
  M := nil;
  if FRoutine.Owner.Parent <> nil then M := FindMethod(FRoutine.Owner.Parent, Name);
  if M = nil then
  begin
    if NT.Kind <> tkIdent then Exit(nil);          // a bare "inherited" with nothing to inherit does nothing
    ErrAt('No inherited method ''' + Name + '''', NT);
  end;
  SelfSym := Lookup('Self');
  Result := BuildMethodCall(VarAccess(SelfSym), FRoutine.Owner, M, True, False);
end;

procedure TCompiler.CheckMethodsDefined;
var
  I: Integer;
begin
  for I := 0 to FForwards.Count - 1 do
    if TRoutine(FForwards[I]).Forward then
      raise EMKCompile.CreateAt('Routine ''' + TRoutine(FForwards[I]).Name + ''' is declared forward but has no body',
        TRoutine(FForwards[I]).DeclLine, 1, FLex.Files[0]);
  for I := 0 to FMethods.Count - 1 do
    if not TRoutine(FMethods[I]).Defined then
      raise EMKCompile.CreateAt('Method ''' + TRoutine(FMethods[I]).Owner.Name + '.' + TRoutine(FMethods[I]).Name +
        ''' has no implementation', TRoutine(FMethods[I]).DeclLine, 1, FLex.Files[0]);
end;

{ New(p, Init(...)) and Dispose(p, Done) }
function TCompiler.ParseNewDispose(Id: TBI; const T: TToken): TStmt;
var
  A, SelfE, Call: TExpr;
  H, Obj: TType;
  S: TBuiltinStmt;
  M: TRoutine;
  MT: TToken;
begin
  ExpectSym('(');
  A := LValueOf(ParseExpr);
  H := HostOf(A.Typ);
  if H.Kind <> tyPtr then ErrAt('Pointer variable expected', T);
  if (Id = biNew) and (H.Base = nil) then ErrAt('Typed pointer variable expected', T);
  S := MakeProc(Id, [A]);
  if Id = biNew then S.Aux := H.Base.Size;
  if AcceptSym(',') then
  begin
    Obj := H.Base;
    if (Obj = nil) or (Obj.Kind <> tyObject) then Err('Constructor and destructor calls need a pointer to an object type');
    MT := Tok;
    M := FindMethod(Obj, ExpectIdent);
    if (M = nil) or ((Id = biNew) and not M.IsCtor) or ((Id = biDispose) and not M.IsDtor) then
      ErrAt('''' + MT.Text + ''' is not a ' + IfThen(Id = biNew, 'constructor', 'destructor') + ' of ' + Obj.Name, MT);
    SelfE := TDerefAddr.Create(RValue(A), Obj);
    Call := BuildMethodCall(SelfE, Obj, M, False, Id = biNew);
    SetLength(S.Args, 2);
    S.Args[1] := Call;
  end;
  ExpectSym(')');
  Result := S;
end;

{ p := New(PType, Init(...)) }
function TCompiler.ParseNewFunc(const T: TToken): TExpr;
var
  E, Slot, SelfE, Call: TExpr;
  H, Obj: TType;
  M: TRoutine;
  MT: TToken;
  B: TBuiltinExpr;
begin
  ExpectSym('(');
  E := ParseExpr;
  if not (E is TTypeRef) or (HostOf(E.Typ).Kind <> tyPtr) then ErrAt('Pointer type expected', T);
  H := HostOf(E.Typ);
  Obj := H.Base;
  if (Obj = nil) or (Obj.Kind <> tyObject) then ErrAt('New as a function needs a pointer to an object type', T);
  ExpectSym(',');
  MT := Tok;
  M := FindMethod(Obj, ExpectIdent);
  if (M = nil) or not M.IsCtor then ErrAt('''' + MT.Text + ''' is not a constructor of ' + Obj.Name, MT);
  Slot := TempVar(FImage.Types.TPointer);
  SelfE := TDerefAddr.Create(TLoad.Create(Slot, FImage.Types.TPointer), Obj);
  Call := BuildMethodCall(SelfE, Obj, M, False, True);
  ExpectSym(')');
  B := MakeFn(biNew, [Slot, Call], E.Typ);
  B.Aux := Obj.Size;
  Result := B;
end;

{ ===================== procedural types ===================== }

function TCompiler.ParseProcType: TType;
var
  IsFunc: Boolean;
  Tmp: TRoutine;
  Off: Integer;
  PT: TType;
begin
  IsFunc := IsKw('function');
  Next;
  PT := FImage.Types.NewType(tyProc);
  PT.Size := 4;
  Tmp := TRoutine.Create;
  try
    Off := 8;
    ParseParams(Tmp, Off);
    while Tmp.Params.Count > 0 do PT.Params.Add(Tmp.Params.Extract(Tmp.Params[0]));
  finally
    Tmp.Free;
  end;
  if IsFunc then
  begin
    ExpectSym(':');
    PT.Ret := ParseType();
  end;
  Result := PT;
end;

{ the value of a routine used as a procedural value: its number in the program's table of routines }
function TCompiler.ProcRef(R: TRoutine; const T: TToken): TExpr;
var
  PT: TType;
  I: Integer;
  P, Q: TParamDesc;
begin
  if R.Owner <> nil then ErrAt('Addresses of methods are not supported', T);
  if R.Level <> 1 then ErrAt('Cannot take the address of the nested routine ''' + R.Name + '''', T);
  if R.ProcId = 0 then
  begin
    FImage.ProcTable.Add(R);
    R.ProcId := FImage.ProcTable.Count;
  end;
  if R.ProcType = nil then
  begin
    PT := FImage.Types.NewType(tyProc);
    PT.Size := 4;
    PT.Ret := R.Ret;
    for I := 0 to R.Params.Count - 1 do
    begin
      P := TParamDesc(R.Params[I]);
      Q := TParamDesc.Create;
      Q.Name := P.Name;
      Q.Typ := P.Typ;
      Q.Mode := P.Mode;
      Q.Offset := P.Offset;
      PT.Params.Add(Q);
    end;
    R.ProcType := PT;
  end;
  Result := TConstInt.Create(R.ProcId, R.ProcType);
end;

{ an expression whose value goes into something of type T: a bare routine name is its address when T is procedural }
function TCompiler.ParseExprFor(T: TType): TExpr;
var
  Sym: TSymbol;
  Skip, K: Integer;
  NT, FirstTok: TToken;
begin
  if (T <> nil) and (HostOf(T).Kind = tyProc) and (Tok.Kind = tkIdent) then
  begin
    FirstTok := Tok;
    Sym := ResolveAhead(Skip);
    if (Sym <> nil) and (Sym.Kind = skRoutine) then
    begin
      NT := PeekTok(Skip + 1);
      if not ((NT.Kind = tkSym) and ((NT.Key = '(') or (NT.Key = '.'))) then
      begin
        for K := 0 to Skip do Next;
        Exit(ProcRef(Sym.Routine, FirstTok));
      end;
    end;
  end;
  Result := ParseExpr;
end;

{ a call through a procedural value }
function TCompiler.BuildProcCall(ProcVal: TExpr): TExpr;
var
  PT: TType;
  Syn: TRoutine;
  Call: TCallExpr;
  I: Integer;
  P, Q: TParamDesc;
begin
  PT := HostOf(ProcVal.Typ);
  Syn := TRoutine.Create;                       // describes the signature for argument checking
  FImage.Routines.Add(Syn);
  Syn.Name := 'procedural value';
  Syn.Level := 1;
  Syn.Ret := PT.Ret;
  for I := 0 to PT.Params.Count - 1 do
  begin
    P := TParamDesc(PT.Params[I]);
    Q := TParamDesc.Create;
    Q.Name := P.Name;
    Q.Typ := P.Typ;
    Q.Mode := P.Mode;
    Q.Offset := P.Offset;
    Syn.Params.Add(Q);
  end;
  Call := TCallExpr.Create(Syn, FLevel);
  Call.Line := Tok.Line;
  Call.ProcExpr := RValue(ProcVal);
  ParseCallArgs(Call, 0);
  if PT.Ret = nil then Call.Typ := FImage.Types.TVoid
  else if PT.Ret.ExprClass = ecMem then Call.TempAddr := TempVar(PT.Ret);
  Result := Call;
end;

{ ===================== goto ===================== }

function TCompiler.LabelKey(const T: TToken): string;
begin
  if T.Kind = tkInt then Result := IntToStr(T.IntVal) else Result := T.Key;
end;

function TCompiler.LabelId(const Key: string): Integer;
begin
  Result := FLabels.Map.IndexOf(Key);
  if Result < 0 then Result := FLabels.Map.Add(Key);
end;

procedure TCompiler.BeginLabelScope(out Saved: TLabelState);
begin
  Saved := FLabels;
  FLabels.Map := TStringList.Create;
  FLabels.Map.CaseSensitive := False;
  FLabels.Stack := TList.Create;
  FLabels.Gotos := TObjectList.Create(True);
  FLabels.Declared := TList.Create;
end;

procedure TCompiler.ResolveGotos;
var
  I, J, K: Integer;
  G: TGotoRec;
  Found: Boolean;
begin
  for I := 0 to FLabels.Gotos.Count - 1 do
  begin
    G := TGotoRec(FLabels.Gotos[I]);
    Found := False;
    for J := 0 to High(G.Frames) do
      for K := 0 to High(G.Frames[J].Ids) do
        if G.Frames[J].Ids[K] = G.Node.LabelId then Found := True;
    if not Found then
      ErrAt('Label ''' + G.Name + ''' is not in an enclosing statement list (goto cannot jump into a statement or out of a routine)', G.Tok);
  end;
end;

procedure TCompiler.EndLabelScope(const Saved: TLabelState);
begin
  FLabels.Map.Free;
  FLabels.Stack.Free;
  FLabels.Gotos.Free;
  FLabels.Declared.Free;
  FLabels := Saved;
end;

function TCompiler.PushLabelFrame: TLabelFrame;
begin
  Result := TLabelFrame.Create;
  FFrames.Add(Result);
  FLabels.Stack.Add(Result);
end;

procedure TCompiler.PopLabelFrame;
begin
  FLabels.Stack.Delete(FLabels.Stack.Count - 1);
end;

function TCompiler.IsLabelAhead: Boolean;
begin
  Result := ((Tok.Kind = tkInt) or (Tok.Kind = tkIdent)) and (PeekTok(1).Kind = tkSym) and (PeekTok(1).Key = ':');
end;

{ label: label: ... at the start of a statement in a list }
procedure TCompiler.ParseLabels(C: TCompound; Frame: TLabelFrame);
var
  Id: Integer;
begin
  while IsLabelAhead do
  begin
    Id := LabelId(LabelKey(Tok));
    if FLabels.Declared.IndexOf(Pointer(PtrInt(Id))) >= 0 then Err('Duplicate label ''' + Tok.Text + '''');
    FLabels.Declared.Add(Pointer(PtrInt(Id)));
    SetLength(Frame.Ids, Length(Frame.Ids) + 1);
    Frame.Ids[High(Frame.Ids)] := Id;
    C.AddLabel(Id);
    Next;
    Next;
  end;
end;

function TCompiler.ParseGoto(const T: TToken): TStmt;
var
  G: TGoto;
  Rec: TGotoRec;
  NT: TToken;
  I: Integer;
begin
  Next;
  if not ((Tok.Kind = tkInt) or (Tok.Kind = tkIdent)) then Err('Label expected but ' + TokDesc + ' found');
  NT := Tok;
  G := TGoto.Create;
  G.Line := T.Line;
  G.LabelId := LabelId(LabelKey(NT));
  Rec := TGotoRec.Create;
  Rec.Node := G;
  Rec.Name := NT.Text;
  Rec.Tok := NT;
  SetLength(Rec.Frames, FLabels.Stack.Count);
  for I := 0 to FLabels.Stack.Count - 1 do Rec.Frames[I] := TLabelFrame(FLabels.Stack[I]);
  FLabels.Gotos.Add(Rec);
  Next;
  Result := G;
end;
