{ ===================== part C: predeclared routines, statements, program ===================== }

{ ---------------- argument lists ---------------- }

procedure TCompiler.ParseArgs(out Args: TExprArray);
begin
  SetLength(Args, 0);
  if not IsSym('(') then Exit;
  Next;
  if AcceptSym(')') then Exit;
  repeat
    SetLength(Args, Length(Args) + 1);
    Args[High(Args)] := ParseExpr;
  until not AcceptSym(',');
  ExpectSym(')');
end;

procedure TCompiler.NeedArgs(const Args: TExprArray; Min, Max: Integer; const T: TToken);
begin
  if Length(Args) < Min then ErrAt('Not enough actual parameters', T);
  if Length(Args) > Max then ErrAt('Too many actual parameters', T);
end;

function TCompiler.IntArg(E: TExpr): TExpr;
begin
  E := RValue(E);
  if HostOf(E.Typ).Kind <> tyInt then Err('Integer expression expected');
  Result := E;
end;

function TCompiler.StrArg(E: TExpr): TExpr;
begin
  Result := Coerce(E, FImage.Types.TString, '');
end;

function TCompiler.RealArg(E: TExpr): TExpr;
begin
  E := RValue(E);
  if not IsNumT(E.Typ) then Err('Numeric expression expected');
  Result := ToReal(E);
end;

function TCompiler.OrdArg(E: TExpr): TExpr;
begin
  E := RValue(E);
  if IsCharLit(E) then E := Coerce(E, FImage.Types.TChar, '');
  if (E.Typ.ExprClass <> ecInt) or not HostOf(E.Typ).IsOrdinal then Err('Ordinal expression expected');
  Result := E;
end;

function TCompiler.FileArg(E: TExpr): TExpr;
begin
  if HostOf(E.Typ).Kind <> tyFile then Err('File variable expected');
  Result := LValueOf(E);
end;

function TCompiler.TypeOfArg(E: TExpr): TType;
begin
  Result := E.Typ;
end;

{ ---------------- functions ---------------- }

function TCompiler.MakeFn(Id: TBI; const Args: array of TExpr; ATyp: TType): TBuiltinExpr;
var
  I: Integer;
begin
  Result := TBuiltinExpr.Create;
  Result.Id := Id;
  Result.Typ := ATyp;
  SetLength(Result.Args, Length(Args));
  for I := 0 to High(Args) do Result.Args[I] := Args[I];
  Result.Soft := (Tok.Sw and SwBit('I')) = 0;
  Result.Line := Tok.Line;
end;

function TCompiler.ParseBuiltinFunc(Id: TBI; const T: TToken): TExpr;
var
  Args: TExprArray;
  A: TExpr;
  B: TBuiltinExpr;
  Ty: TType;
  N: Int64;
  I: Integer;
  M, M2: Int64;
  Folds: Boolean;
begin
  if Id = biNew then Exit(ParseNewFunc(T));
  if Id > biAddr then ErrAt('''' + T.Text + ''' is a procedure and has no value', T);
  Result := nil;
  Ty := FImage.Types.TVoid;
  if (Id = biSizeOf) or (Id = biHigh) or (Id = biLow) then
  begin
    ParseArgs(Args);
    NeedArgs(Args, 1, 1, T);
    A := Args[0];
    Ty := A.Typ;
    if (Id <> biSizeOf) and (HostOf(Ty).Kind = tyOpenArray) then
    begin
      if Id = biLow then Exit(TConstInt.Create(0, FImage.Types.TInteger));
      Exit(TOpenHigh.Create(A, FImage.Types.TLongInt));
    end;
    case Id of
      biSizeOf: begin N := Ty.Size; Exit(TConstInt.Create(N, FImage.Types.IntTypeFor(N, N))); end;
      biHigh, biLow:
        begin
          Ty := HostOf(Ty);
          case Ty.Kind of
            tyArray: if Id = biHigh then N := Ty.Hi else N := Ty.Lo;
            tyString: if Id = biHigh then N := Ty.MaxLen else N := 0;
            tyInt, tyBool, tyChar, tyEnum:
              if Id = biHigh then N := A.Typ.Hi else N := A.Typ.Lo;
          else
            Err('Invalid argument to High/Low');
            N := 0;
          end;
          if Ty.Kind in [tyArray, tyString] then Exit(TConstInt.Create(N, FImage.Types.IntTypeFor(N, N)));
          if Ty.Kind = tyInt then Exit(TConstInt.Create(N, FImage.Types.IntTypeFor(N, N)));
          Exit(TConstInt.Create(N, Ty));
        end;
    end;
  end;
  if Id = biAddr then
  begin
    ParseArgs(Args);
    NeedArgs(Args, 1, 1, T);
    A := LValueOf(Args[0]);
    Exit(TAddrOf.Create(A, FImage.Types.PtrType(A.Typ)));
  end;
  ParseArgs(Args);
  case Id of
    biAbs, biSqr:
      begin
        NeedArgs(Args, 1, 1, T);
        A := RValue(Args[0]);
        if HostOf(A.Typ).Kind = tyReal then Ty := A.Typ
        else if HostOf(A.Typ).Kind = tyInt then
        begin
          M := Abs(A.Typ.Lo);
          if Abs(A.Typ.Hi) > M then M := Abs(A.Typ.Hi);
          if Id = biSqr then M := M * M;
          Ty := FImage.Types.IntTypeFor(0, M);
        end
        else Err('Numeric expression expected');
        B := MakeFn(Id, [A], Ty);
      end;
    biSqrt, biSin, biCos, biArcTan, biLn, biExp, biInt, biFrac:
      begin
        NeedArgs(Args, 1, 1, T);
        B := MakeFn(Id, [RealArg(Args[0])], FImage.Types.TReal);
      end;
    biPi:
      begin
        NeedArgs(Args, 0, 0, T);
        B := MakeFn(Id, [], FImage.Types.TReal);
      end;
    biRound, biTrunc:
      begin
        NeedArgs(Args, 1, 1, T);
        B := MakeFn(Id, [RealArg(Args[0])], FImage.Types.TLongInt);
      end;
    biOdd:
      begin
        NeedArgs(Args, 1, 1, T);
        B := MakeFn(Id, [IntArg(Args[0])], FImage.Types.TBoolean);
      end;
    biOrd:
      begin
        NeedArgs(Args, 1, 1, T);
        A := OrdArg(Args[0]);
        B := MakeFn(Id, [A], FImage.Types.IntTypeFor(A.Typ.Lo, A.Typ.Hi));
      end;
    biChr:
      begin
        NeedArgs(Args, 1, 1, T);
        B := MakeFn(Id, [IntArg(Args[0])], FImage.Types.TChar);
      end;
    biSucc, biPred:
      begin
        NeedArgs(Args, 1, 1, T);
        A := OrdArg(Args[0]);
        B := MakeFn(Id, [A], A.Typ);
      end;
    biLength:
      begin
        NeedArgs(Args, 1, 1, T);
        B := MakeFn(Id, [StrArg(Args[0])], FImage.Types.TInteger);
      end;
    biCopy:
      begin
        NeedArgs(Args, 3, 3, T);
        B := MakeFn(Id, [StrArg(Args[0]), IntArg(Args[1]), IntArg(Args[2])], FImage.Types.TString);
      end;
    biPos:
      begin
        NeedArgs(Args, 2, 2, T);
        B := MakeFn(Id, [StrArg(Args[0]), StrArg(Args[1])], FImage.Types.TInteger);
      end;
    biConcat:
      begin
        NeedArgs(Args, 1, 255, T);
        B := MakeFn(Id, [], FImage.Types.TString);
        SetLength(B.Args, Length(Args));
        for I := 0 to High(Args) do B.Args[I] := StrArg(Args[I]);
      end;
    biUpCase:
      begin
        NeedArgs(Args, 1, 1, T);
        B := MakeFn(Id, [Coerce(Args[0], FImage.Types.TChar, '')], FImage.Types.TChar);
      end;
    biLowerCase, biUpperCase:
      begin
        NeedArgs(Args, 1, 1, T);
        B := MakeFn(Id, [StrArg(Args[0])], FImage.Types.TString);
      end;
    biRandom:
      begin
        NeedArgs(Args, 0, 1, T);
        if Length(Args) = 0 then B := MakeFn(Id, [], FImage.Types.TReal)
        else B := MakeFn(Id, [IntArg(Args[0])], FImage.Types.TWord);
      end;
    biEof, biEoln, biSeekEof, biSeekEoln:
      begin
        NeedArgs(Args, 0, 1, T);
        if Length(Args) = 1 then B := MakeFn(Id, [FileArg(Args[0])], FImage.Types.TBoolean)
        else B := MakeFn(Id, [], FImage.Types.TBoolean);
      end;
    biFilePos, biFileSize:
      begin
        NeedArgs(Args, 1, 1, T);
        B := MakeFn(Id, [FileArg(Args[0])], FImage.Types.TLongInt);
      end;
    biIOResult:
      begin
        NeedArgs(Args, 0, 0, T);
        B := MakeFn(Id, [], FImage.Types.TWord);
      end;
    biHi, biLo:
      begin
        NeedArgs(Args, 1, 1, T);
        B := MakeFn(Id, [IntArg(Args[0])], FImage.Types.TByte);
      end;
    biSwap:
      begin
        NeedArgs(Args, 1, 1, T);
        B := MakeFn(Id, [IntArg(Args[0])], FImage.Types.TWord);
      end;
    biParamCount:
      begin
        NeedArgs(Args, 0, 0, T);
        B := MakeFn(Id, [], FImage.Types.TWord);
      end;
    biParamStr:
      begin
        NeedArgs(Args, 1, 1, T);
        B := MakeFn(Id, [IntArg(Args[0])], FImage.Types.TString);
      end;
    biReadKey:
      begin
        NeedArgs(Args, 0, 0, T);
        B := MakeFn(Id, [], FImage.Types.TChar);
      end;
    biKeyPressed:
      begin
        NeedArgs(Args, 0, 0, T);
        B := MakeFn(Id, [], FImage.Types.TBoolean);
      end;
    biWhereX, biWhereY:
      begin
        NeedArgs(Args, 0, 0, T);
        B := MakeFn(Id, [], FImage.Types.TByte);
      end;
    biAssigned:
      begin
        NeedArgs(Args, 1, 1, T);
        B := MakeFn(Id, [RValue(Args[0])], FImage.Types.TBoolean);
      end;
    biMemAvail, biMaxAvail:
      begin
        NeedArgs(Args, 0, 0, T);
        B := MakeFn(Id, [], FImage.Types.TLongInt);
      end;
    biTypeOf:
      begin
        NeedArgs(Args, 1, 1, T);
        A := Args[0];
        if (A is TTypeRef) then
        begin
          if HostOf(A.Typ).Kind <> tyObject then Err('Object type expected');
          Exit(TConstInt.Create(HostOf(A.Typ).VmtId, FImage.Types.TPointer));
        end;
        if HostOf(A.Typ).Kind <> tyObject then Err('Object type or variable expected');
        if HostOf(A.Typ).VmtOff < 0 then Err('The object type has no virtual methods');
        B := MakeFn(Id, [LValueOf(A)], FImage.Types.TPointer);
        B.Aux := HostOf(A.Typ).VmtOff;
      end;
    biDosVersion:
      begin
        NeedArgs(Args, 0, 0, T);
        B := MakeFn(Id, [], FImage.Types.TWord);
      end;
    biGetEnv, biFExpand:
      begin
        NeedArgs(Args, 1, 1, T);
        B := MakeFn(Id, [StrArg(Args[0])], FImage.Types.TString);
      end;
  else
    ErrAt('Unsupported function', T);
    B := nil;
  end;
  Result := B;
  { fold calls on constants (Chr(27), Length('abc'), Ord('A') ...) }
  if not (Id in [biRandom, biEof, biEoln, biSeekEof, biSeekEoln, biFilePos, biFileSize, biIOResult,
                 biParamCount, biParamStr, biReadKey, biKeyPressed, biWhereX, biWhereY, biMemAvail, biMaxAvail,
                 biTypeOf, biDosVersion, biGetEnv, biFExpand]) then
  begin
    Folds := True;
    for I := 0 to High(B.Args) do
      if not B.Args[I].IsConst then Folds := False;
    if Folds then Result := TryFold(B);
  end;
end;

{ ---------------- procedures ---------------- }

function TCompiler.MakeProc(Id: TBI; const Args: array of TExpr): TBuiltinStmt;
var
  I: Integer;
begin
  Result := TBuiltinStmt.Create;
  Result.Id := Id;
  SetLength(Result.Args, Length(Args));
  for I := 0 to High(Args) do Result.Args[I] := Args[I];
  Result.Soft := (Tok.Sw and SwBit('I')) = 0;
  Result.Line := Tok.Line;
end;

procedure TCompiler.ParseFormatted(out E, W, D: TExpr);
begin
  E := ParseExpr;
  W := nil;
  D := nil;
  if AcceptSym(':') then
  begin
    W := IntArg(ParseExpr);
    if AcceptSym(':') then D := IntArg(ParseExpr);
  end;
end;

function TCompiler.ParseWrite(NewLine: Boolean; const T: TToken): TStmt;
var
  W: TWriteStmt;
  It: TWriteItem;
  E, Wd, Dc: TExpr;
  First: Boolean;
  H: TType;
  FileType: TType;
begin
  W := TWriteStmt.Create;
  W.NewLine := NewLine;
  W.Soft := (T.Sw and SwBit('I')) = 0;
  W.Line := T.Line;
  FileType := nil;
  if AcceptSym('(') then
  begin
    First := True;
    repeat
      ParseFormatted(E, Wd, Dc);
      if First and (HostOf(E.Typ).Kind = tyFile) then
      begin
        FileType := HostOf(E.Typ);
        W.FileE := LValueOf(E);
        W.TypedFile := (FileType.Elem <> nil);
        First := False;
        Continue;
      end;
      First := False;
      It := TWriteItem.Create;
      W.Items.Add(It);
      E := RValue(E);
      if W.TypedFile then
      begin
        It.Expr := Coerce(E, FileType.Elem, ' in Write');
        It.Typ := FileType.Elem;
        It.Temp := TempVar(FileType.Elem);
        Continue;
      end;
      if (FileType <> nil) and not FileType.IsText then Err('Write cannot be used with an untyped file');
      It.Expr := E;
      It.Width := Wd;
      It.Dec := Dc;
      H := HostOf(E.Typ);
      It.Typ := H;
      case H.Kind of
        tyInt: It.Kind := wkInt;
        tyReal: It.Kind := wkReal;
        tyBool: It.Kind := wkBool;
        tyChar: It.Kind := wkChar;
        tyString: It.Kind := wkStr;
        tyEnum: It.Kind := wkEnum;
      else
        Err('Cannot write values of type ' + TypeName(E.Typ));
      end;
    until not AcceptSym(',');
    ExpectSym(')');
  end;
  if W.TypedFile and NewLine then ErrAt('WriteLn needs a text file', T);
  Result := W;
end;

function TCompiler.ParseRead(NewLine: Boolean; const T: TToken): TStmt;
var
  R: TReadStmt;
  Tg: TReadTarget;
  E: TExpr;
  First: Boolean;
  H, FileType: TType;
begin
  R := TReadStmt.Create;
  R.NewLine := NewLine;
  R.Soft := (T.Sw and SwBit('I')) = 0;
  R.Line := T.Line;
  FileType := nil;
  if AcceptSym('(') then
  begin
    First := True;
    repeat
      E := ParseExpr;
      if First and (HostOf(E.Typ).Kind = tyFile) then
      begin
        FileType := HostOf(E.Typ);
        R.FileE := LValueOf(E);
        R.TypedFile := FileType.Elem <> nil;
        First := False;
        Continue;
      end;
      First := False;
      Tg := TReadTarget.Create;
      R.Targets.Add(Tg);
      Tg.Addr := LValueOf(E);
      Tg.Typ := HostOf(Tg.Addr.Typ);
      H := Tg.Typ;
      if R.TypedFile then
      begin
        if not Assignable(FileType.Elem, Tg.Addr.Typ) or (FileType.Elem.Size <> Tg.Addr.Typ.Size) then
          Err('Type of variable does not match the file''s element type');
      end
      else
      begin
        if (FileType <> nil) and not FileType.IsText then Err('Read cannot be used with an untyped file');
        if not (H.Kind in [tyChar, tyInt, tyReal, tyString]) then Err('Cannot read values of type ' + TypeName(Tg.Addr.Typ));
      end;
    until not AcceptSym(',');
    ExpectSym(')');
  end;
  if R.TypedFile and NewLine then ErrAt('ReadLn needs a text file', T);
  Result := R;
end;

function TCompiler.ParseBuiltinStmt(Id: TBI; const T: TToken): TStmt;
var
  Args: TExprArray;
  S: TBuiltinStmt;
  A, B, C, D: TExpr;
  H: TType;
  I: Integer;
begin
  if Id <= biAddr then ErrAt('''' + T.Text + ''' is a function and cannot be used as a statement', T);
  if Id = biWrite then Exit(ParseWrite(False, T));
  if Id = biWriteLn then Exit(ParseWrite(True, T));
  if Id = biRead then Exit(ParseRead(False, T));
  if Id = biReadLn then Exit(ParseRead(True, T));
  if (Id = biNew) or (Id = biDispose) then Exit(ParseNewDispose(Id, T));
  if Id = biStr then
  begin
    ExpectSym('(');
    ParseFormatted(A, B, C);
    ExpectSym(',');
    D := LValueOf(ParseExpr);
    ExpectSym(')');
    A := RValue(A);
    if not IsNumT(A.Typ) then Err('Numeric expression expected');
    if HostOf(D.Typ).Kind <> tyString then Err('String variable expected');
    S := MakeProc(biStr, [A, B, C, D]);
    Exit(S);
  end;
  ParseArgs(Args);
  case Id of
    biExit, biBreak, biContinue:
      begin
        NeedArgs(Args, 0, 0, T);
        if Id = biExit then Result := TSignal.Create(sgExit)
        else
        begin
          if FLoopDepth = 0 then ErrAt('''' + T.Text + ''' outside of a loop', T);
          if Id = biBreak then Result := TSignal.Create(sgBreak) else Result := TSignal.Create(sgContinue);
        end;
        Result.Line := T.Line;
        Exit;
      end;
    biInc, biDec:
      begin
        NeedArgs(Args, 1, 2, T);
        A := LValueOf(Args[0]);
        H := HostOf(A.Typ);
        if not (H.Kind in [tyInt, tyChar, tyEnum]) then Err('Ordinal variable expected');
        if Length(Args) = 2 then S := MakeProc(Id, [A, IntArg(Args[1])]) else S := MakeProc(Id, [A]);
      end;
    biNew:
      begin
        NeedArgs(Args, 1, 1, T);
        A := LValueOf(Args[0]);
        H := HostOf(A.Typ);
        if (H.Kind <> tyPtr) or (H.Base = nil) then Err('Typed pointer variable expected');
        S := MakeProc(Id, [A]);
        S.Aux := H.Base.Size;
      end;
    biDispose, biFreeMem:
      begin
        NeedArgs(Args, 1, 2, T);
        A := LValueOf(Args[0]);
        if HostOf(A.Typ).Kind <> tyPtr then Err('Pointer variable expected');
        if Length(Args) = 2 then RValue(Args[1]);
        S := MakeProc(Id, [A]);
      end;
    biGetMem:
      begin
        NeedArgs(Args, 2, 2, T);
        A := LValueOf(Args[0]);
        if HostOf(A.Typ).Kind <> tyPtr then Err('Pointer variable expected');
        S := MakeProc(Id, [A, IntArg(Args[1])]);
      end;
    biFillChar:
      begin
        NeedArgs(Args, 3, 3, T);
        C := RValue(Args[2]);
        if IsCharLit(C) then C := Coerce(C, FImage.Types.TChar, '');
        S := MakeProc(Id, [LValueOf(Args[0]), IntArg(Args[1]), C]);
      end;
    biMove:
      begin
        NeedArgs(Args, 3, 3, T);
        S := MakeProc(Id, [LValueOf(Args[0]), LValueOf(Args[1]), IntArg(Args[2])]);
      end;
    biInsert:
      begin
        NeedArgs(Args, 3, 3, T);
        B := LValueOf(Args[1]);
        if HostOf(B.Typ).Kind <> tyString then Err('String variable expected');
        S := MakeProc(Id, [StrArg(Args[0]), B, IntArg(Args[2])]);
      end;
    biDelete:
      begin
        NeedArgs(Args, 3, 3, T);
        A := LValueOf(Args[0]);
        if HostOf(A.Typ).Kind <> tyString then Err('String variable expected');
        S := MakeProc(Id, [A, IntArg(Args[1]), IntArg(Args[2])]);
      end;
    biVal:
      begin
        NeedArgs(Args, 3, 3, T);
        B := LValueOf(Args[1]);
        if not (HostOf(B.Typ).Kind in [tyInt, tyReal]) then Err('Numeric variable expected');
        C := LValueOf(Args[2]);
        if HostOf(C.Typ).Kind <> tyInt then Err('Integer variable expected');
        S := MakeProc(Id, [StrArg(Args[0]), B, C]);
      end;
    biHalt:
      begin
        NeedArgs(Args, 0, 1, T);
        if Length(Args) = 1 then S := MakeProc(Id, [IntArg(Args[0])]) else S := MakeProc(Id, []);
      end;
    biRandomize:
      begin
        NeedArgs(Args, 0, 0, T);
        S := MakeProc(Id, []);
      end;
    biInclude, biExclude:
      begin
        NeedArgs(Args, 2, 2, T);
        A := LValueOf(Args[0]);
        if HostOf(A.Typ).Kind <> tySet then Err('Set variable expected');
        S := MakeProc(Id, [A, OrdArg(Args[1])]);
      end;
    biAssign, biRename:
      begin
        NeedArgs(Args, 2, 2, T);
        A := FileArg(Args[0]);
        S := MakeProc(Id, [A, StrArg(Args[1])]);
        S.IsText := HostOf(A.Typ).IsText;
      end;
    biReset, biRewrite:
      begin
        NeedArgs(Args, 1, 2, T);
        A := FileArg(Args[0]);
        H := HostOf(A.Typ);
        if Length(Args) = 2 then S := MakeProc(Id, [A, IntArg(Args[1])]) else S := MakeProc(Id, [A]);
        if (H.Elem <> nil) and not H.IsText then begin S.Typed := True; S.RecSize := H.Elem.Size; end;
      end;
    biAppend, biClose, biErase, biFlush, biTruncate:
      begin
        NeedArgs(Args, 1, 1, T);
        S := MakeProc(Id, [FileArg(Args[0])]);
      end;
    biSeek:
      begin
        NeedArgs(Args, 2, 2, T);
        A := FileArg(Args[0]);
        H := HostOf(A.Typ);
        S := MakeProc(Id, [A, IntArg(Args[1])]);
        if (H.Elem <> nil) and not H.IsText then begin S.Typed := True; S.RecSize := H.Elem.Size; end;
      end;
    biBlockRead, biBlockWrite:
      begin
        NeedArgs(Args, 3, 4, T);
        A := FileArg(Args[0]);
        if Length(Args) = 4 then
        begin
          D := LValueOf(Args[3]);
          S := MakeProc(Id, [A, LValueOf(Args[1]), IntArg(Args[2]), D]);
        end
        else
          S := MakeProc(Id, [A, LValueOf(Args[1]), IntArg(Args[2])]);
      end;
    biSetTextBuf:
      begin
        NeedArgs(Args, 2, 2, T);
        S := MakeProc(Id, []);
      end;
    biClrScr, biClrEol, biNoSound, biHighVideo, biLowVideo, biNormVideo:
      begin
        NeedArgs(Args, 0, 0, T);
        S := MakeProc(Id, []);
      end;
    biGotoXY:
      begin
        NeedArgs(Args, 2, 2, T);
        S := MakeProc(Id, [IntArg(Args[0]), IntArg(Args[1])]);
      end;
    biFail:
      begin
        NeedArgs(Args, 0, 0, T);
        if (FRoutine = nil) or not FRoutine.IsCtor then ErrAt('Fail can only be used inside a constructor', T);
        S := MakeProc(Id, []);
      end;
    biGetDate, biGetTime:
      begin
        NeedArgs(Args, 4, 4, T);
        S := MakeProc(Id, [LValueOf(Args[0]), LValueOf(Args[1]), LValueOf(Args[2]), LValueOf(Args[3])]);
        for I := 0 to 3 do
          if HostOf(S.Args[I].Typ).Kind <> tyInt then Err('Integer variable expected');
      end;
    biFSplit:
      begin
        NeedArgs(Args, 4, 4, T);
        S := MakeProc(Id, [StrArg(Args[0]), LValueOf(Args[1]), LValueOf(Args[2]), LValueOf(Args[3])]);
        for I := 1 to 3 do
          if HostOf(S.Args[I].Typ).Kind <> tyString then Err('String variable expected');
      end;
    biFindFirst:
      begin
        NeedArgs(Args, 3, 3, T);
        A := LValueOf(Args[2]);
        if A.Typ <> FSearchRecType then Err('SearchRec variable expected');
        S := MakeProc(Id, [StrArg(Args[0]), IntArg(Args[1]), A]);
      end;
    biFindNext, biFindClose:
      begin
        NeedArgs(Args, 1, 1, T);
        A := LValueOf(Args[0]);
        if A.Typ <> FSearchRecType then Err('SearchRec variable expected');
        S := MakeProc(Id, [A]);
      end;
    biGetFTime:
      begin
        NeedArgs(Args, 2, 2, T);
        B := LValueOf(Args[1]);
        if HostOf(B.Typ).Kind <> tyInt then Err('LongInt variable expected');
        S := MakeProc(Id, [FileArg(Args[0]), B]);
      end;
    biSetFTime:
      begin
        NeedArgs(Args, 2, 2, T);
        S := MakeProc(Id, [FileArg(Args[0]), IntArg(Args[1])]);
      end;
    biPackTime:
      begin
        NeedArgs(Args, 2, 2, T);
        A := LValueOf(Args[0]);
        B := LValueOf(Args[1]);
        if A.Typ <> FDateTimeType then Err('DateTime variable expected');
        if HostOf(B.Typ).Kind <> tyInt then Err('LongInt variable expected');
        S := MakeProc(Id, [A, B]);
      end;
    biUnpackTime:
      begin
        NeedArgs(Args, 2, 2, T);
        B := LValueOf(Args[1]);
        if B.Typ <> FDateTimeType then Err('DateTime variable expected');
        S := MakeProc(Id, [IntArg(Args[0]), B]);
      end;
    biTextColor, biTextBackground, biDelay, biSound:
      begin
        NeedArgs(Args, 1, 1, T);
        S := MakeProc(Id, [IntArg(Args[0])]);
      end;
  else
    ErrAt('Unsupported procedure', T);
    S := nil;
  end;
  Result := S;
end;

{ ---------------- statements ---------------- }

function TCompiler.ParseCompound: TStmt;
var
  C: TCompound;
  S: TStmt;
  Frame: TLabelFrame;
begin
  ExpectKw('begin');
  C := TCompound.Create;
  C.Line := Tok.Line;
  Frame := PushLabelFrame;
  while True do
  begin
    ParseLabels(C, Frame);
    S := ParseStatement();
    if not (S is TNop) then C.Add(S);
    if AcceptSym(';') then Continue;
    Break;
  end;
  PopLabelFrame;
  ExpectKw('end');
  Result := C;
end;

function TCompiler.ParseStmtList(const Stops: array of string): TStmt;
var
  C: TCompound;
  S: TStmt;
  I: Integer;
  AtStop: Boolean;
  Frame: TLabelFrame;
begin
  C := TCompound.Create;
  C.Line := Tok.Line;
  Frame := PushLabelFrame;
  while True do
  begin
    ParseLabels(C, Frame);
    S := ParseStatement();
    if not (S is TNop) then C.Add(S);
    if AcceptSym(';') then Continue;
    AtStop := Tok.Kind = tkEOF;
    for I := 0 to High(Stops) do
      if (Tok.Kind = tkKeyword) and (Tok.Key = Stops[I]) then AtStop := True;
    if AtStop then Break;
    Err('''' + Stops[0] + ''' expected but ' + TokDesc + ' found');
  end;
  PopLabelFrame;
  Result := C;
end;

function TCompiler.ParseStatement: TStmt;
var
  T: TToken;
  Sym: TSymbol;
  E, Dst, Src: TExpr;
  A: TAssign;
  Call: TCallExpr;
  CS: TCallStmt;
  Cond: TExpr;
  I: TIf;
  W: TWhile;
  R: TRepeat;
  F: TFor;
  V: TExpr;
  C: TCase;
  Arm: TCaseArm;
  Lo, Hi: TExpr;
  Comp: TCompound;
  Slot: TExpr;
  Rec: TType;
  SavedScope: TScope;
  K: Integer;
  Fld: TField;
  FS: TSymbol;
  WX: TType;
  Body: TStmt;
  Soft: Boolean;
  SkipN: Integer;
begin
  T := Tok;
  Result := nil;
  if IsLabelAhead then Err('Labels are only allowed in statement lists');
  if (Tok.Kind = tkKeyword) then
  begin
    if IsKw('begin') then Exit(ParseCompound);
    if IsKw('if') then
    begin
      Next;
      Cond := RValue(ParseExpr);
      if HostOf(Cond.Typ).Kind <> tyBool then Err('Boolean expression expected');
      ExpectKw('then');
      I := TIf.Create;
      I.Line := T.Line;
      I.Cond := Cond;
      I.ThenS := ParseStatement();
      if AcceptKw('else') then I.ElseS := ParseStatement();
      Exit(I);
    end;
    if IsKw('while') then
    begin
      Next;
      Cond := RValue(ParseExpr);
      if HostOf(Cond.Typ).Kind <> tyBool then Err('Boolean expression expected');
      ExpectKw('do');
      W := TWhile.Create;
      W.Line := T.Line;
      W.Cond := Cond;
      Inc(FLoopDepth);
      W.Body := ParseStatement();
      Dec(FLoopDepth);
      Exit(W);
    end;
    if IsKw('repeat') then
    begin
      Next;
      R := TRepeat.Create;
      R.Line := T.Line;
      Inc(FLoopDepth);
      R.Body := ParseStmtList(['until']);
      Dec(FLoopDepth);
      ExpectKw('until');
      Cond := RValue(ParseExpr);
      if HostOf(Cond.Typ).Kind <> tyBool then Err('Boolean expression expected');
      R.Cond := Cond;
      Exit(R);
    end;
    if IsKw('for') then
    begin
      Next;
      if Tok.Kind <> tkIdent then Err('Identifier expected but ' + TokDesc + ' found');
      V := ParseFactor;
      if not V.IsLValue or not HostOf(V.Typ).IsOrdinal then Err('For loop control variable must be an ordinal variable');
      F := TFor.Create;
      F.Line := T.Line;
      F.VarAddr := V;
      ExpectSym(':=');
      F.First := Coerce(ParseExpr, V.Typ, ' in for loop');
      if AcceptKw('downto') then F.Down := True else ExpectKw('to');
      F.Last := Coerce(ParseExpr, V.Typ, ' in for loop');
      ExpectKw('do');
      Inc(FLoopDepth);
      F.Body := ParseStatement();
      Dec(FLoopDepth);
      Exit(F);
    end;
    if IsKw('case') then
    begin
      Next;
      C := TCase.Create;
      C.Line := T.Line;
      C.Sel := OrdArg(ParseExpr);
      ExpectKw('of');
      while not IsKw('end') and not IsKw('else') do
      begin
        Arm := TCaseArm.Create;
        C.Arms.Add(Arm);
        repeat
          Lo := Coerce(RValue(ParseExpr), C.Sel.Typ, ' in case label');
          ConstOf(Lo);
          Hi := Lo;
          if AcceptSym('..') then
          begin
            Hi := Coerce(RValue(ParseExpr), C.Sel.Typ, ' in case label');
            ConstOf(Hi);
          end;
          SetLength(Arm.Los, Length(Arm.Los) + 1);
          SetLength(Arm.His, Length(Arm.His) + 1);
          Arm.Los[High(Arm.Los)] := Lo.EvalI(nil);
          Arm.His[High(Arm.His)] := Hi.EvalI(nil);
        until not AcceptSym(',');
        ExpectSym(':');
        Arm.Body := ParseStatement();
        if not AcceptSym(';') then Break;
      end;
      if AcceptKw('else') then C.ElseS := ParseStmtList(['end']);
      ExpectKw('end');
      Exit(C);
    end;
    if IsKw('with') then
    begin
      Next;
      Comp := TCompound.Create;
      Comp.Line := T.Line;
      SavedScope := FScope;
      PushScope;
      repeat
        E := ParseExpr;
        Rec := HostOf(E.Typ);
        if not (Rec.Kind in [tyRecord, tyObject]) then Err('Record type expected in ''with''');
        Slot := TempVar(FImage.Types.TPointer);
        Comp.Add(TAssign.Create(Slot, TAddrOf.Create(LValueOf(E), FImage.Types.TPointer)));
        for K := 0 to Rec.Fields.Count - 1 do
        begin
          Fld := TField(Rec.Fields[K]);
          FS := NewSym(Fld.Name, skField);
          FS.Typ := Fld.Typ;
          FS.Offset := Fld.Offset;
          FS.Slot := Slot;
          FS.RecType := Rec;
          if FScope.Find(Fld.Name) <> nil then FScope.Syms.Delete(FScope.Syms.IndexOf(Fld.Name));
          FScope.Syms.AddObject(Fld.Name, FS);
        end;
        if Rec.Kind = tyObject then
        begin
          WX := Rec;
          while WX <> nil do
          begin
            for K := 0 to WX.Methods.Count - 1 do
              if FScope.Find(WX.Methods[K]) = nil then
              begin
                FS := NewSym(WX.Methods[K], skMethod);
                FS.Routine := TRoutine(WX.Methods.Objects[K]);
                FS.Slot := Slot;
                FS.RecType := Rec;
                FScope.Syms.AddObject(WX.Methods[K], FS);
              end;
            WX := WX.Parent;
          end;
        end;
      until not AcceptSym(',');
      ExpectKw('do');
      Body := ParseStatement();
      Comp.Add(Body);
      FScope := SavedScope;
      Exit(Comp);
    end;
    if IsKw('goto') then Exit(ParseGoto(T));
    if IsKw('inherited') then
    begin
      E := ParseInherited(False);
      if E = nil then Exit(TNop.Create);
      CS := TCallStmt.Create;
      CS.Call := TCallExpr(E);
      CS.Line := T.Line;
      Exit(CS);
    end;
    if IsKw('asm') then Err('Inline assembler is not supported');
    if IsKw('end') or IsKw('else') or IsKw('until') then Exit(TNop.Create);
    Err('Statement expected but ' + TokDesc + ' found');
  end;
  if IsSym(';') then Exit(TNop.Create);
  if Tok.Kind <> tkIdent then Err('Statement expected but ' + TokDesc + ' found');

  Sym := ResolveAhead(SkipN);
  if Sym = nil then Err('Unknown identifier ''' + Tok.Text + '''');
  if (Sym.Kind = skBuiltin) then
  begin
    for K := 0 to SkipN do Next;
    Result := ParseBuiltinStmt(Sym.BI, T);
    Result.Line := T.Line;
    Exit;
  end;
  if (Sym.Kind = skMethod) and (FRoutine <> nil) and (FRoutine = Sym.Routine) and (FRoutine.Ret <> nil) and
     (PeekTok(1).Kind = tkSym) and (PeekTok(1).Key = ':=') then
  begin
    Next;
    Dst := TLocalAddr.Create(FRoutine.ResultOffset, FLevel - FRoutine.Level, FRoutine.Ret);
  end
  else if Sym.Kind = skRoutine then
  begin
    { the name of the function being compiled on the left of := is its result }
    if (FRoutine <> nil) and (FRoutine = Sym.Routine) and (FRoutine.Ret <> nil) and
       (PeekTok(SkipN + 1).Kind = tkSym) and (PeekTok(SkipN + 1).Key = ':=') then
    begin
      for K := 0 to SkipN do Next;
      Dst := TLocalAddr.Create(FRoutine.ResultOffset, FLevel - FRoutine.Level, FRoutine.Ret);
    end
    else
    begin
      for K := 0 to SkipN do Next;
      Call := ParseCall(Sym.Routine);
      CS := TCallStmt.Create;
      CS.Call := Call;
      CS.Line := T.Line;
      Exit(CS);
    end;
  end
  else
    Dst := ParseFactor;
  if IsSym(':=') then
  begin
    Next;
    if not Dst.IsLValue then ErrAt('Variable expected', T);
    if HostOf(Dst.Typ).Kind = tyFile then Err('Files cannot be assigned');
    Src := Coerce(ParseExprFor(Dst.Typ), Dst.Typ, ' in assignment');
    A := TAssign.Create(Dst, Src);
    A.Line := T.Line;
    Exit(A);
  end;
  { a call through a procedural value without parameters: f; or rec.cb; }
  if Dst.IsLValue and (HostOf(Dst.Typ).Kind = tyProc) then
  begin
    CS := TCallStmt.Create;
    CS.Call := TCallExpr(BuildProcCall(Dst));
    CS.Line := T.Line;
    Exit(CS);
  end;
  { a call of a function whose result is ignored, or a typecast used as a statement }
  if Dst is TCallExpr then
  begin
    CS := TCallStmt.Create;
    CS.Call := TCallExpr(Dst);
    CS.Line := T.Line;
    Exit(CS);
  end;
  ErrAt('Statement expected', T);
end;

{ ---------------- program ---------------- }

procedure TCompiler.ParseProgram;
var
  Main: TStmt;
  Comp: TCompound;
  I: Integer;
  SavedLabels: TLabelState;
begin
  FImage.Name := '';
  if AcceptKw('program') then
  begin
    FImage.Name := ExpectIdent;
    if AcceptSym('(') then
    begin
      repeat
        ExpectIdent;
      until not AcceptSym(',');
      ExpectSym(')');
    end;
    ExpectSym(';');
  end;
  FScope := NewImportScope(FRoot);              // what the uses clause imports
  ParseUses;
  PushScope;
  ParseDecls;
  BeginLabelScope(SavedLabels);
  Main := ParseCompound;
  ResolveGotos;
  EndLabelScope(SavedLabels);
  ExpectSym('.');
  if Tok.Kind <> tkEOF then Err('Unexpected text after the final ''end.''');
  CheckMethodsDefined;
  { unit initialization parts run first, dependencies before their users }
  Comp := TCompound.Create;
  for I := 0 to FImage.UnitInits.Count - 1 do Comp.Add(TStmt(FImage.UnitInits[I]));
  Comp.Add(Main);
  FImage.Main := Comp;
  FImage.GlobalEnd := FGlobalTop;
end;

constructor TCompiler.Create(AInclude: TIncludeFunc; AUnitSource: TUnitSourceFunc; ADefines: TStrings; AMaxGlobals: LongWord);
begin
  inherited Create;
  FInclude := AInclude;
  FUnitSource := AUnitSource;
  FDefines := ADefines;
  FMaxGlobals := AMaxGlobals;
  FUnits := TStringList.Create;
  FUnits.CaseSensitive := False;
  FUnits.OwnsObjects := True;
  FMethods := TList.Create;
  FForwards := TList.Create;
  FFrames := TObjectList.Create(True);
end;

destructor TCompiler.Destroy;
begin
  FLex.Free;
  FUnits.Free;
  FMethods.Free;
  FForwards.Free;
  FFrames.Free;
  inherited Destroy;
end;

function TCompiler.Compile(const Src: string): TProgramImage;
begin
  FImage := TProgramImage.Create;
  Result := FImage;
  NodePool := FImage.Pool;
  try
    FLex := TLexer.Create(FInclude, FDefines);
    FLex.Tokenize(Src);
    FPos := 0;
    Tok := FLex.Toks[0];
    FGlobalTop := 16;
    FLevel := 0;
    InstallPredeclared;
    ParseProgram;
  except
    NodePool := nil;
    FreeAndNil(FImage);
    raise;
  end;
  NodePool := nil;
end;
