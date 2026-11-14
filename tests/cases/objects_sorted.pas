program ObjSorted;
uses Objects;
type
  PNum = ^TNum;
  TNum = object(TObject)
    V: Integer;
    constructor Init(A: Integer);
  end;
  PNumList = ^TNumList;
  TNumList = object(TSortedCollection)
    function Compare(K1, K2: Pointer): Integer; virtual;
  end;
constructor TNum.Init(A: Integer); begin V := A; end;
function TNumList.Compare(K1, K2: Pointer): Integer;
begin
  Compare := PNum(K1)^.V - PNum(K2)^.V;
end;
procedure Dump(P: Pointer); far;
begin Write(PNum(P)^.V, ' '); end;
procedure DumpS(P: Pointer); far;
begin Write(PString(P)^, ' '); end;
procedure DumpC(P: Pointer); far;
begin Write(PChar(P), ' '); end;
var
  L: PNumList;
  S: PStringCollection;
  C: PStrCollection;
  I, Idx: Integer;
  Vals: array[1..7] of Integer;
  N: PNum;
  Key: TNum;
  buf: array[0..9] of char;
  pc: PChar;
begin
  Vals[1] := 5; Vals[2] := 1; Vals[3] := 9; Vals[4] := 3; Vals[5] := 5; Vals[6] := 7; Vals[7] := 2;
  L := New(PNumList, Init(2, 2));
  for I := 1 to 7 do L^.Insert(New(PNum, Init(Vals[I])));
  L^.ForEach(@Dump); WriteLn(' count=', L^.Count);
  L^.Duplicates := True;
  L^.Insert(New(PNum, Init(5)));
  L^.ForEach(@Dump); WriteLn(' count=', L^.Count);
  Key.Init(7);
  WriteLn(L^.Search(@Key, Idx), ' ', Idx);
  Key.Init(4);
  WriteLn(L^.Search(@Key, Idx), ' ', Idx);
  N := L^.At(3);
  WriteLn(L^.IndexOf(N), ' ', N^.V);
  Dispose(L, Done);

  S := New(PStringCollection, Init(4, 4));
  S^.Insert(NewStr('pear'));
  S^.Insert(NewStr('apple'));
  S^.Insert(NewStr('fig'));
  S^.Insert(NewStr('apple'));
  S^.ForEach(@DumpS); WriteLn(S^.Count);
  Dispose(S, Done);

  C := New(PStrCollection, Init(4, 4));
  StrCopy(buf, 'zeta');
  C^.Insert(StrNew(buf));
  C^.Insert(StrNew('alpha'));
  C^.Insert(StrNew('mu'));
  C^.ForEach(@DumpC); WriteLn;
  pc := StrNew('mu');
  WriteLn(C^.Search(pc, Idx), ' ', Idx);
  StrDispose(pc);
  C^.AtFree(0);
  C^.ForEach(@DumpC); WriteLn;
  Dispose(C, Done);
  WriteLn(MemAvail > 0);
end.
