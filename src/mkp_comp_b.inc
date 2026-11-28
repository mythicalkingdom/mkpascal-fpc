{ SPDX-License-Identifier: GPL-3.0-or-later }
{ ===================== part B: expressions ===================== }

function IsLoadNode(E: TExpr): Boolean;
begin
  Result := (E is TLoad) or (E is TLoadGlobalInt) or (E is TLoadLocalInt);
end;

function TCompiler.IsCharLit(E: TExpr): Boolean;
begin
  Result := (E is TConstStr) and (Length(TConstStr(E).Value) = 1);
end;

function TCompiler.RValue(E: TExpr): TExpr;
begin
  if E.Typ.Kind = tyUntyped then
    Err('An untyped parameter can only be passed on to an untyped parameter, to Move, FillChar, BlockRead or BlockWrite, or typecast');
  if E.IsLValue and (E.Typ.ExprClass <> ecMem) then
  begin
    if (E.Typ.ExprClass = ecInt) and (E is TGlobalAddr) then
      Result := TLoadGlobalInt.Create(TGlobalAddr(E).Addr, E.Typ)
    else if (E.Typ.ExprClass = ecInt) and (E is TLocalAddr) and (TLocalAddr(E).Hops = 0) then
      Result := TLoadLocalInt.Create(TLocalAddr(E).Offset, E.Typ)
    else
      Result := TLoad.Create(E, E.Typ);
    Result.Line := E.Line;
  end
  else
    Result := E;
end;

function TCompiler.LValueOf(E: TExpr): TExpr;
begin
  if E is TLoad then Exit(TLoad(E).Addr);
  if E is TLoadGlobalInt then Exit(TGlobalAddr.Create(TLoadGlobalInt(E).Addr, E.Typ));
  if E is TLoadLocalInt then Exit(TLocalAddr.Create(TLoadLocalInt(E).Offset, 0, E.Typ));
  if E.IsLValue and (E.Typ.Kind = tyOpenArray) then Exit(TOpenData.Create(E, FImage.Types.TUntyped));
  if E.IsLValue then Exit(E);
  Err('Variable expected');
  Result := nil;
end;

function TCompiler.IsIntT(T: TType): Boolean;
begin
  Result := HostOf(T).Kind = tyInt;
end;

function TCompiler.IsNumT(T: TType): Boolean;
begin
  Result := HostOf(T).Kind in [tyInt, tyReal];
end;

function TCompiler.ToReal(E: TExpr): TExpr;
begin
  if E.Typ.Kind = tyReal then Exit(E);
  Result := TIntToReal.Create(E, FImage.Types.TReal);
end;

function TCompiler.ToStr(E: TExpr): TExpr;
begin
  if IsCharLit(E) and False then Exit(E);
  if HostOf(E.Typ).Kind = tyChar then Result := TCharToStr.Create(E, FImage.Types.TString) else Result := E;
end;

function TCompiler.ArithType(L, R: TType): TType;
var
  Lo, Hi: Int64;
begin
  Lo := L.Lo;
  if R.Lo < Lo then Lo := R.Lo;
  Hi := L.Hi;
  if R.Hi > Hi then Hi := R.Hi;
  Result := FImage.Types.IntTypeFor(Lo, Hi);
end;

function TCompiler.WrapOf(T: TType): TWrap;
begin
  if T = FImage.Types.TInteger then Result := wI16
  else if T = FImage.Types.TWord then Result := wU16
  else Result := wI32;
end;

function TCompiler.IsPCharT(T: TType): Boolean;
var
  H: TType;
begin
  H := HostOf(T);
  Result := (H.Kind = tyPtr) and (H.Base <> nil) and (HostOf(H.Base).Kind = tyChar);
end;

{ string constants and zero based character arrays become PChar values }
function TCompiler.PCharArg(E: TExpr): TExpr;
var
  A: TAddr;
  H: TType;
  Buf: RawByteString;
begin
  if (E is TConstStr) then
  begin
    Buf := RawByteString(string(TConstStr(E).Value)) + #0;
    A := AllocGlobal(Length(Buf));
    AddInit(A, Buf);
    Exit(TConstInt.Create(A, FImage.Types.TPChar));
  end;
  H := HostOf(E.Typ);
  if E.IsLValue and (H.Kind = tyArray) and (HostOf(H.Elem).Kind = tyChar) and (H.Lo = 0) then
    Exit(TAddrOf.Create(E, FImage.Types.TPChar));
  Result := RValue(E);
  if not IsPCharT(Result.Typ) and not (HostOf(Result.Typ).Kind in [tyNil]) and
     not ((HostOf(Result.Typ).Kind = tyPtr) and (HostOf(Result.Typ).Base = nil)) then
    Err('PChar, a string constant or a zero based character array expected');
end;

{ convert E so that it can be stored in a variable of type Dst (or passed to a parameter of that type) }
function TCompiler.Coerce(E: TExpr; Dst: TType; const What: string): TExpr;
var
  D, S: TType;
  V: Int64;
  Mismatch: Boolean;
begin
  if IsPCharT(Dst) and ((E is TConstStr) or (E.IsLValue and (HostOf(E.Typ).Kind = tyArray))) then
    Exit(PCharArg(E));
  if (HostOf(Dst).Kind = tyString) and E.IsLValue and (HostOf(E.Typ).Kind = tyArray) and
     (HostOf(HostOf(E.Typ).Elem).Kind = tyChar) and (HostOf(E.Typ).Lo = 0) then
    Exit(TPCharToStr.Create(PCharArg(E), FImage.Types.TString));
  E := RValue(E);
  D := HostOf(Dst);
  S := HostOf(E.Typ);
  if S.Kind = tyVoid then Err('Expression has no value');
  Result := E;
  Mismatch := False;
  case D.Kind of
    tyChar:
      if IsCharLit(E) then Result := TConstInt.Create(Ord(TConstStr(E).Value[1]), Dst)
      else Mismatch := S.Kind <> tyChar;
    tyString:
      begin
        if S.Kind = tyChar then Result := TCharToStr.Create(E, FImage.Types.TString)
        else if IsPCharT(S) then Result := TPCharToStr.Create(E, FImage.Types.TString)
        else Mismatch := S.Kind <> tyString;
      end;
    tyInt:
      begin
        if S.Kind <> tyInt then Mismatch := True
        else if E.IsConst then
        begin
          V := E.EvalI(nil);
          if (V < Dst.Lo) or (V > Dst.Hi) then
            Err('Constant out of range: ' + IntToStr(V) + ' is not in ' + IntToStr(Dst.Lo) + '..' + IntToStr(Dst.Hi));
          Result := TConstInt.Create(V, Dst);
        end
        else if (Tok.Sw and SwBit('R')) <> 0 then
        begin
          if (E.Typ.Lo < Dst.Lo) or (E.Typ.Hi > Dst.Hi) then Result := TIntCast.Create(E, Dst, True);
        end;
      end;
    tyReal:
      begin
        if S.Kind = tyInt then Result := TIntToReal.Create(E, Dst)
        else Mismatch := S.Kind <> tyReal;
      end;
    tyBool, tyEnum:
      Mismatch := (S.Kind <> D.Kind) or ((D.Kind = tyEnum) and (D <> S));
    tyPtr, tyProc:
      Mismatch := not Assignable(Dst, E.Typ);
    tySet:
      Mismatch := not ((S.Kind = tySet) and ((E.Typ.Base = nil) or SameType(D, S)));
    tyArray, tyRecord, tyObject, tyFile:
      Mismatch := not Assignable(Dst, E.Typ);
  else
    Mismatch := True;
  end;
  if Mismatch then
  begin
    Err('Type mismatch' + What + ': cannot convert ' + TypeName(E.Typ) + ' to ' + TypeName(Dst));
  end;
end;

{ ---------------- selectors ---------------- }

function TCompiler.ParseSelectors(Base: TExpr): TExpr;
var
  F: TField;
  Idx: TExpr;
  T: TType;
  M: TRoutine;
begin
  Result := Base;
  while True do
  begin
    if IsSym('.') then
    begin
      Next;
      T := HostOf(Result.Typ);
      if not (T.Kind in [tyRecord, tyObject]) then Err('Record type expected before ''.''');
      F := T.FindField(Tok.Text);
      if (F = nil) and (T.Kind = tyObject) then
      begin
        M := FindMethod(T, Tok.Text);
        if M <> nil then
        begin
          Next;
          Result := BuildMethodCall(Result, T, M, False, True);
          Result.Line := Tok.Line;
          Continue;
        end;
      end;
      if (Tok.Kind <> tkIdent) or (F = nil) then Err('Unknown field ''' + Tok.Text + '''');
      Next;
      Result := TFieldAddr.Create(Result, F.Offset, F.Typ);
    end
    else if IsSym('[') then
    begin
      Next;
      repeat
        T := HostOf(Result.Typ);
        Idx := RValue(ParseExpr);
        if T.Kind = tyString then
        begin
          Idx := Coerce(Idx, FImage.Types.TInteger, ' in string index');
          if not Result.IsLValue then Result := TTempStr.Create(Result, TempVar(FImage.Types.TString), FImage.Types.TString);
          Result := TStrElemAddr.Create(Result, Idx, T.MaxLen, FImage.Types.TChar);
        end
        else if IsPCharT(T) then
        begin
          if (Idx.Typ.ExprClass <> ecInt) or (HostOf(Idx.Typ).Kind <> tyInt) then Err('Integer expression expected in index');
          Result := TPtrIndexAddr.Create(RValue(Result), Idx, FImage.Types.TChar);
        end
        else if T.Kind = tyOpenArray then
        begin
          if (Idx.Typ.ExprClass <> ecInt) or (HostOf(Idx.Typ).Kind <> tyInt) then Err('Integer expression expected in array index');
          Result := TOpenIndexAddr.Create(Result, Idx, T.Elem.Size, T.Elem);
        end
        else if T.Kind = tyArray then
        begin
          if IsCharLit(Idx) then Idx := Coerce(Idx, FImage.Types.TChar, '');
          if (Idx.Typ.ExprClass <> ecInt) or not HostOf(Idx.Typ).IsOrdinal then Err('Ordinal expression expected in array index');
          Result := TIndexAddr.Create(Result, Idx, T.Lo, T.Hi, T.Elem.Size, T.Elem);
        end
        else
          Err('Array type expected before ''[''');
      until not AcceptSym(',');
      ExpectSym(']');
    end
    else if IsSym('(') and (HostOf(Result.Typ).Kind = tyProc) then
      Result := BuildProcCall(Result)
    else if IsSym('^') then
    begin
      Next;
      T := HostOf(Result.Typ);
      if (T.Kind <> tyPtr) or (T.Base = nil) then Err('Typed pointer expected before ''^''');
      Result := TDerefAddr.Create(RValue(Result), T.Base);
    end
    else
      Break;
    Result.Line := Tok.Line;
  end;
end;

{ ---------------- primary expressions ---------------- }

function TCompiler.ParseSetLiteral: TExpr;
var
  Lo, Hi: TExpr;
  Cons: TSetCons;
  Base: TType;
  AllConst: Boolean;
  SV: TSetVal;
begin
  ExpectSym('[');
  Cons := TSetCons.Create(nil);
  Base := nil;
  AllConst := True;
  if not IsSym(']') then
  begin
    repeat
      Lo := RValue(ParseExpr);
      if IsCharLit(Lo) then Lo := Coerce(Lo, FImage.Types.TChar, '');
      if (Lo.Typ.ExprClass <> ecInt) or not HostOf(Lo.Typ).IsOrdinal then Err('Ordinal expression expected in set');
      if Base = nil then Base := HostOf(Lo.Typ);
      Hi := nil;
      if AcceptSym('..') then
      begin
        Hi := RValue(ParseExpr);
        if IsCharLit(Hi) then Hi := Coerce(Hi, FImage.Types.TChar, '');
        if not Hi.IsConst then AllConst := False;
      end;
      if not Lo.IsConst then AllConst := False;
      Cons.Add(Lo, Hi);
    until not AcceptSym(',');
  end;
  ExpectSym(']');
  if Base = nil then
    Cons.Typ := FImage.Types.SetType(nil)
  else
  begin
    if Base.Kind = tyInt then Base := FImage.Types.TByte;
    Cons.Typ := FImage.Types.SetType(Base);
    Cons.Typ.Size := 32;          // literals have room for any element; stores copy the variable's size
  end;
  Result := Cons;
  if AllConst then
  begin
    FillChar(SV, SizeOf(SV), 0);
    Cons.EvalSet(nil, SV);
    Result := TConstSet.Create(SV, Cons.Typ);
  end;
end;

function TCompiler.ParseTypecast(T: TType): TExpr;
var
  A, V: TExpr;
  DH, AH: TType;
  Sz: Integer;
begin
  ExpectSym('(');
  A := ParseExpr;
  ExpectSym(')');
  DH := HostOf(T);
  if IsCharLit(A) and (DH.Kind <> tyString) then A := Coerce(A, FImage.Types.TChar, '');
  AH := HostOf(A.Typ);
  if DH.IsOrdinal and AH.IsOrdinal and (A.Typ.ExprClass = ecInt) then
  begin
    V := RValue(A);
    if DH.Kind = tyBool then
      Result := TCmpInt.Create(cNe, V, TConstInt.Create(0, FImage.Types.TByte), FImage.Types.TBoolean)
    else
      Result := TIntCast.Create(V, T, False);
    if V.IsConst then Result := TryFold(Result);
    Exit;
  end;
  if (DH.Kind = tyReal) and (AH.Kind in [tyInt, tyReal]) then
  begin
    V := RValue(A);
    if AH.Kind = tyInt then Result := TIntToReal.Create(V, T) else Result := TRetypeVal.Create(V, T);
    Exit;
  end;
  if (DH.Kind = tyString) and (AH.Kind in [tyString, tyChar]) then
    Exit(Coerce(A, T, ' in type cast'));
  if (DH.Kind in [tyPtr, tyProc]) and (A.Typ.ExprClass = ecInt) and not (AH.Kind = tyChar) then
  begin
    Exit(TRetypeVal.Create(RValue(A), T));
  end;
  { a variable typecast: the same bytes seen as another type of the same size }
  if A.IsLValue or IsLoadNode(A) then
  begin
    V := LValueOf(A);
    Sz := V.Typ.Size;
    if (V.Typ.Kind <> tyUntyped) and (Sz <> T.Size) then Err('Invalid type cast (the types have different sizes)');
    Exit(TRetype.Create(V, T));
  end;
  if (A.Typ.ExprClass = ecMem) and (A.Typ.Size = T.Size) then Exit(TRetype.Create(A, T));
  Err('Invalid type cast');
  Result := nil;
end;

function TCompiler.ParseCallExpr(R: TRoutine): TExpr;
var
  Call: TCallExpr;
begin
  Call := ParseCall(R);
  if R.Ret = nil then
  begin
    { a procedure used as a value }
    Call.Typ := FImage.Types.TVoid;
  end;
  Result := Call;
end;

function TCompiler.ParseCall(R: TRoutine): TCallExpr;
var
  Call: TCallExpr;
begin
  Call := TCallExpr.Create(R, FLevel);
  Call.Line := Tok.Line;
  ParseCallArgs(Call, 0);
  if (R.Ret <> nil) and (R.Ret.ExprClass = ecMem) then Call.TempAddr := TempVar(R.Ret);
  Result := Call;
end;

function TCompiler.ParseFactor: TExpr;
var
  T: TToken;
  Sym: TSymbol;
  E: TExpr;
  S: ShortString;
  V: Int64;
  M: TRoutine;
  SkipN, K: Integer;
begin
  T := Tok;
  case Tok.Kind of
    tkInt:
      begin
        Next;
        Result := TConstInt.Create(T.IntVal, FImage.Types.IntTypeFor(T.IntVal, T.IntVal));
      end;
    tkReal:
      begin
        Next;
        Result := TConstReal.Create(T.RealVal, FImage.Types.TReal);
      end;
    tkString:
      begin
        Next;
        S := T.Text;
        Result := TConstStr.Create(S, FImage.Types.TString);
      end;
    tkKeyword:
      begin
        if IsKw('nil') then begin Next; Result := TConstInt.Create(0, FImage.Types.TNil); end
        else if IsKw('not') then
        begin
          Next;
          E := RValue(ParseFactor());
          Result := BuildNot(E);
        end
        else if IsKw('inherited') then Result := ParseInherited(True)
        else if IsKw('string') then
        begin
          Next;
          if IsSym('(') then Result := ParseSelectors(ParseTypecast(FImage.Types.TString))
          else begin Result := TTypeRef.Create; Result.Typ := FImage.Types.TString; end;
        end
        else Err('Expression expected but ' + TokDesc + ' found');
      end;
    tkSym:
      begin
        if IsSym('(') then
        begin
          Next;
          Result := ParseExpr;
          ExpectSym(')');
        end
        else if IsSym('@') then
        begin
          Next;
          if Tok.Kind = tkIdent then
          begin
            Sym := ResolveAhead(SkipN);
            if (Sym <> nil) and (Sym.Kind = skBuiltin) then Err('Cannot take the address of a standard routine');
            if (Sym <> nil) and (Sym.Kind = skRoutine) then
            begin
              T := Tok;
              for K := 0 to SkipN do Next;
              Exit(ProcRef(Sym.Routine, T));
            end;
          end;
          E := ParseFactor();
          E := LValueOf(E);
          Result := TAddrOf.Create(E, FImage.Types.PtrType(E.Typ));
        end
        else if IsSym('[') then Result := ParseSetLiteral
        else Err('Expression expected but ' + TokDesc + ' found');
      end;
    tkIdent:
      begin
        Sym := ResolveCurrent;
        if Sym = nil then Err('Unknown identifier ''' + Tok.Text + '''');
        case Sym.Kind of
          skConst:
            begin
              Next;
              Result := Sym.Expr;
            end;
          skType:
            begin
              Next;
              if IsSym('(') then Result := ParseSelectors(ParseTypecast(Sym.Typ))
              else if IsSym('.') and (Sym.Typ.Kind = tyObject) then
              begin
                { TParent.Method(...) inside a method of a descendant: a static call on Self }
                Next;
                M := FindMethod(Sym.Typ, Tok.Text);
                if M = nil then Err('Unknown method ''' + Tok.Text + '''');
                if (FRoutine = nil) or (FRoutine.Owner = nil) or not IsDescendant(FRoutine.Owner, Sym.Typ) then
                  Err('''' + Sym.Typ.Name + '.' + Tok.Text + ''' can only be called from a method of a descendant type');
                Next;
                Result := ParseSelectors(BuildMethodCall(VarAccess(Lookup('Self')), Sym.Typ, M, True, False));
              end
              else
              begin
                Result := TTypeRef.Create;
                Result.Typ := Sym.Typ;
              end;
            end;
          skMethod:
            begin
              Next;
              Result := ParseSelectors(BuildMethodCall(ObjAddrOfMethodSym(Sym), Sym.RecType, Sym.Routine, False, True));
            end;
          skVar:
            begin
              Next;
              Result := ParseSelectors(VarAccess(Sym));
            end;
          skField:
            begin
              Next;
              Result := ParseSelectors(FieldAccess(Sym));
            end;
          skRoutine:
            begin
              Next;
              Result := ParseCallExpr(Sym.Routine);
              if Result.Typ.Kind <> tyVoid then Result := ParseSelectors(Result);
            end;
          skBuiltin:
            begin
              Next;
              Result := ParseBuiltinFunc(Sym.BI, T);
            end;
        else
          Err('Cannot use ''' + Sym.Name + ''' here');
          Result := nil;
        end;
      end;
  else
    Err('Expression expected but ' + TokDesc + ' found');
    Result := nil;
  end;
  if Result.Line = 0 then Result.Line := T.Line;
end;

function TCompiler.FieldAccess(Sym: TSymbol): TExpr;
begin
  if Sym.SelfSym <> nil then
  begin
    Result := TFieldAddr.Create(VarAccess(Sym.SelfSym), Sym.Offset, Sym.Typ);
    Exit;
  end;
  { a field of a record named in a with statement: the slot holds the record's address }
  Result := TFieldAddr.Create(TDerefAddr.Create(TLoad.Create(Sym.Slot, FImage.Types.TPointer), Sym.RecType), Sym.Offset, Sym.Typ);
end;

{ ---------------- operators ---------------- }

function TCompiler.BuildNot(E: TExpr): TExpr;
var
  H: TType;
begin
  H := HostOf(E.Typ);
  if H.Kind = tyBool then Result := TBoolNot.Create(E, FImage.Types.TBoolean)
  else if H.Kind = tyInt then
  begin
    if (E.Typ = FImage.Types.TByte) or (E.Typ = FImage.Types.TWord) or (E.Typ = FImage.Types.TInteger) or (E.Typ = FImage.Types.TShortInt) then
      Result := TIntUn.Create(True, E, WrapOf(E.Typ), E.Typ)
    else
      Result := TIntUn.Create(True, E, wI32, FImage.Types.TLongInt);
    if (E.Typ = FImage.Types.TByte) then TIntUn(Result).Wrap := wU16;
  end
  else
    Err('Operator ''not'' not applicable to ' + TypeName(E.Typ));
  if E.IsConst then Result := TryFold(Result);
end;

function TCompiler.BuildBinary(const Op: string; L, R: TExpr; const T: TToken): TExpr;
var
  LH, RH: TType;
  AT: TType;
  AOp: TArithOp;
  C: TCmp;
  FoldV: Int64;
  Wr: TWrap;
  Ls, Rs: TExpr;

  procedure Bad;
  begin
    ErrAt('Operator ''' + Op + ''' not applicable to ' + TypeName(L.Typ) + ' and ' + TypeName(R.Typ), T);
  end;

begin
  L := RValue(L);
  R := RValue(R);
  { a one character string constant next to a Char is a Char }
  if IsCharLit(L) and (HostOf(R.Typ).Kind = tyChar) then L := Coerce(L, FImage.Types.TChar, '');
  if IsCharLit(R) and (HostOf(L.Typ).Kind = tyChar) then R := Coerce(R, FImage.Types.TChar, '');
  if IsPCharT(L.Typ) and R.IsLValue and (HostOf(R.Typ).Kind = tyArray) then R := PCharArg(R);
  if IsPCharT(R.Typ) and L.IsLValue and (HostOf(L.Typ).Kind = tyArray) then L := PCharArg(L);
  LH := HostOf(L.Typ);
  RH := HostOf(R.Typ);
  if (LH.Kind = tyVoid) or (RH.Kind = tyVoid) then Err('Expression has no value');
  Result := nil;

  if Op = 'in' then
  begin
    if IsCharLit(L) and (RH.Kind = tySet) then begin L := Coerce(L, FImage.Types.TChar, ''); LH := HostOf(L.Typ); end;
    if (RH.Kind <> tySet) or not LH.IsOrdinal then Bad;
    Result := TSetIn.Create(L, R, FImage.Types.TBoolean);
    if L.IsConst and R.IsConst then Result := TryFold(Result);
    Exit;
  end;

  if (Op = '=') or (Op = '<>') or (Op = '<') or (Op = '>') or (Op = '<=') or (Op = '>=') then
  begin
    if Op = '=' then C := cEq else if Op = '<>' then C := cNe else if Op = '<' then C := cLt
    else if Op = '>' then C := cGt else if Op = '<=' then C := cLe else C := cGe;
    if (LH.Kind in [tyInt, tyReal]) and (RH.Kind in [tyInt, tyReal]) then
    begin
      if (LH.Kind = tyReal) or (RH.Kind = tyReal) then
        Result := TCmpReal.Create(C, ToReal(L), ToReal(R), FImage.Types.TBoolean)
      else
        Result := TCmpInt.Create(C, L, R, FImage.Types.TBoolean);
    end
    else if (LH.Kind in [tyString, tyChar]) and (RH.Kind in [tyString, tyChar]) then
    begin
      if (LH.Kind = tyChar) and (RH.Kind = tyChar) then Result := TCmpInt.Create(C, L, R, FImage.Types.TBoolean)
      else Result := TCmpStr.Create(C, ToStr(L), ToStr(R), FImage.Types.TBoolean);
    end
    else if (LH.Kind = RH.Kind) and (LH.Kind in [tyBool, tyChar]) then
      Result := TCmpInt.Create(C, L, R, FImage.Types.TBoolean)
    else if (LH.Kind = tyEnum) and (LH = RH) then
      Result := TCmpInt.Create(C, L, R, FImage.Types.TBoolean)
    else if (LH.Kind in [tyPtr, tyNil, tyProc]) and (RH.Kind in [tyPtr, tyNil, tyProc]) then
    begin
      if not (C in [cEq, cNe]) then Bad;
      Result := TCmpInt.Create(C, L, R, FImage.Types.TBoolean);
    end
    else if (LH.Kind = tySet) and (RH.Kind = tySet) then
    begin
      if not (C in [cEq, cNe, cLe, cGe]) then Bad;
      Result := TCmpSet.Create(C, L, R, FImage.Types.TBoolean);
    end
    else
      Bad;
    if L.IsConst and R.IsConst then Result := TryFold(Result);
    Exit;
  end;

  if (Op = '+') or (Op = '-') or (Op = '*') then
  begin
    if (LH.Kind = tySet) and (RH.Kind = tySet) then
    begin
      Result := TSetBin.Create(Op[1], L, R, L.Typ);
      if L.IsConst and R.IsConst then Result := TryFold(Result);
      Exit;
    end;
    if (Op = '+') and (LH.Kind in [tyString, tyChar]) and (RH.Kind in [tyString, tyChar]) then
    begin
      Result := TStrConcat.Create(ToStr(L), ToStr(R), FImage.Types.TString);
      if L.IsConst and R.IsConst then Result := TryFold(Result);
      Exit;
    end;
    if (LH.Kind = tyReal) or (RH.Kind = tyReal) then
    begin
      if not (IsNumT(LH) and IsNumT(RH)) then Bad;
      if LH.Kind = tyReal then AT := L.Typ else AT := R.Typ;
      Result := TRealBin.Create(Op[1], ToReal(L), ToReal(R), AT);
      if L.IsConst and R.IsConst then Result := TryFold(Result);
      Exit;
    end;
    if IsPCharT(LH) and (Op <> '*') then
    begin
      if (RH.Kind = tyInt) then
      begin
        if Op = '+' then AOp := aoAdd else AOp := aoSub;
        Exit(TIntBin.Create(AOp, L, R, wNone, LH));
      end;
      if (Op = '-') and IsPCharT(RH) then
        Exit(TIntBin.Create(aoSub, L, R, wI32, FImage.Types.TLongInt));
      Bad;
    end;
    if (LH.Kind = tyInt) and (RH.Kind = tyInt) then
    begin
      if L.IsConst and R.IsConst then
      begin
        if Op = '+' then FoldV := L.EvalI(nil) + R.EvalI(nil)
        else if Op = '-' then FoldV := L.EvalI(nil) - R.EvalI(nil)
        else FoldV := L.EvalI(nil) * R.EvalI(nil);
        Exit(TConstInt.Create(FoldV, FImage.Types.IntTypeFor(FoldV, FoldV)));
      end;
      AT := ArithType(L.Typ, R.Typ);
      if Op = '+' then AOp := aoAdd else if Op = '-' then AOp := aoSub else AOp := aoMul;
      Exit(TIntBin.Create(AOp, L, R, WrapOf(AT), AT));
    end;
    Bad;
  end;

  if Op = '/' then
  begin
    if not (IsNumT(LH) and IsNumT(RH)) then Bad;
    Result := TRealBin.Create('/', ToReal(L), ToReal(R), FImage.Types.TReal);
    if L.IsConst and R.IsConst then Result := TryFold(Result);
    Exit;
  end;

  if (Op = 'div') or (Op = 'mod') or (Op = 'shl') or (Op = 'shr') then
  begin
    if (LH.Kind <> tyInt) or (RH.Kind <> tyInt) then Bad;
    if Op = 'div' then AOp := aoDiv else if Op = 'mod' then AOp := aoMod else if Op = 'shl' then AOp := aoShl else AOp := aoShr;
    if (AOp in [aoShl, aoShr]) then AT := ArithType(L.Typ, L.Typ) else AT := ArithType(L.Typ, R.Typ);
    Result := TIntBin.Create(AOp, L, R, WrapOf(AT), AT);
    if L.IsConst and R.IsConst then
    begin
      Result := TryFold(Result);
      if Result is TConstInt then TConstInt(Result).Typ := FImage.Types.IntTypeFor(TConstInt(Result).Value, TConstInt(Result).Value);
    end;
    Exit;
  end;

  if (Op = 'and') or (Op = 'or') or (Op = 'xor') then
  begin
    if (LH.Kind = tyBool) and (RH.Kind = tyBool) then
    begin
      if Op = 'and' then Result := TBoolBin.Create('&', L, R, FImage.Types.TBoolean)
      else if Op = 'or' then Result := TBoolBin.Create('|', L, R, FImage.Types.TBoolean)
      else Result := TBoolBin.Create('^', L, R, FImage.Types.TBoolean);
      if L.IsConst and R.IsConst then Result := TryFold(Result);
      Exit;
    end;
    if (LH.Kind = tyInt) and (RH.Kind = tyInt) then
    begin
      AT := ArithType(L.Typ, R.Typ);
      if Op = 'and' then AOp := aoAnd else if Op = 'or' then AOp := aoOr else AOp := aoXor;
      Result := TIntBin.Create(AOp, L, R, WrapOf(AT), AT);
      if L.IsConst and R.IsConst then Result := TryFold(Result);
      Exit;
    end;
    Bad;
  end;
  Err('Unsupported operator ''' + Op + '''');
end;

function TCompiler.ParseTerm: TExpr;
var
  L, R: TExpr;
  Op: string;
  T: TToken;
begin
  L := ParseFactor;
  while IsSym('*') or IsSym('/') or IsKw('div') or IsKw('mod') or IsKw('and') or IsKw('shl') or IsKw('shr') do
  begin
    T := Tok;
    Op := Tok.Key;
    Next;
    R := ParseFactor;
    L := BuildBinary(Op, L, R, T);
  end;
  Result := L;
end;

function TCompiler.ParseSimpleExpr: TExpr;
var
  L, R, E: TExpr;
  Op: string;
  T: TToken;
  H: TType;
  Ty: TType;
begin
  if IsSym('-') or IsSym('+') then
  begin
    T := Tok;
    Op := Tok.Key;
    Next;
    E := RValue(ParseTerm);
    H := HostOf(E.Typ);
    if Op = '-' then
    begin
      if H.Kind = tyReal then L := TRealNeg.Create(E, E.Typ)
      else if H.Kind = tyInt then
      begin
        Ty := FImage.Types.IntTypeFor(-E.Typ.Hi, -E.Typ.Lo);
        L := TIntUn.Create(False, E, WrapOf(Ty), Ty);
      end
      else
      begin
        ErrAt('Operator ''-'' not applicable to ' + TypeName(E.Typ), T);
        L := nil;
      end;
      if E.IsConst then
      begin
        L := TryFold(L);
        if L is TConstInt then TConstInt(L).Typ := FImage.Types.IntTypeFor(TConstInt(L).Value, TConstInt(L).Value);
      end;
    end
    else
    begin
      if not IsNumT(H) then ErrAt('Operator ''+'' not applicable to ' + TypeName(E.Typ), T);
      L := E;
    end;
  end
  else
    L := ParseTerm;
  while IsSym('+') or IsSym('-') or IsKw('or') or IsKw('xor') do
  begin
    T := Tok;
    Op := Tok.Key;
    Next;
    R := ParseTerm;
    L := BuildBinary(Op, L, R, T);
  end;
  Result := L;
end;

function TCompiler.ParseExpr: TExpr;
var
  L, R: TExpr;
  Op: string;
  T: TToken;
begin
  L := ParseSimpleExpr;
  while (Tok.Kind = tkSym) and ((Tok.Key = '=') or (Tok.Key = '<>') or (Tok.Key = '<') or (Tok.Key = '>') or
    (Tok.Key = '<=') or (Tok.Key = '>=')) or IsKw('in') do
  begin
    T := Tok;
    Op := Tok.Key;
    Next;
    R := ParseSimpleExpr;
    L := BuildBinary(Op, L, R, T);
  end;
  Result := L;
end;
