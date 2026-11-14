program O1;
uses Objects;
type
  PItem = ^TItem;
  TItem = object(TObject)
    N: Integer;
    constructor Init(A: Integer);
    destructor Done; virtual;
  end;
constructor TItem.Init(A: Integer); begin N := A; end;
destructor TItem.Done; begin WriteLn('free ', N); end;
procedure Show(P: Pointer); far;
begin WriteLn('item ', PItem(P)^.N); end;
function Big(P: Pointer): Boolean; far;
begin Big := PItem(P)^.N > 5; end;
var
  C: PCollection;
  I: Integer;
  R: TRect; P: TPoint;
begin
  C := New(PCollection, Init(2, 2));
  for I := 1 to 8 do C^.Insert(New(PItem, Init(I * 2)));
  C^.ForEach(@Show);
  WriteLn(PItem(C^.FirstThat(@Big))^.N, ' ', PItem(C^.LastThat(@Big))^.N, ' ', C^.Count);
  C^.AtFree(0);
  Dispose(C, Done);
  R.Assign(0,0,10,10); P.X := 3; P.Y := 4;
  WriteLn(R.Contains(P), R.Empty);
end.
