program R4;
type
  TP = record X, Y: Integer; end;
  TR = object
    A, B: TP;
    procedure Show;
    procedure Take(Q: TR);
  end;
procedure TR.Show; begin WriteLn(A.X, ' ', B.X); end;
procedure TR.Take(Q: TR); begin WriteLn('in'); Q.Show; WriteLn(Q.B.X); end;
var S, T: TR;
begin
  S.A.X := 1; T.A.X := 2; T.B.X := 3;
  WriteLn(SizeOf(TR));
  S.Show;
  S.Take(T);
end.
