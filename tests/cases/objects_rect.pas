program ObjRect;
uses Objects;
var
  A, B: TRect;
  P: TPoint;
  O: PObject;
begin
  A.Assign(0, 0, 10, 10);
  B.Assign(5, 5, 20, 8);
  A.Intersect(B);
  WriteLn(A.A.X, ',', A.A.Y, ' ', A.B.X, ',', A.B.Y, ' ', A.Empty);
  A.Union(B);
  A.Grow(1, 2);
  A.Move(3, 3);
  WriteLn(A.A.X, ',', A.A.Y, ' ', A.B.X, ',', A.B.Y);
  P.X := 10; P.Y := 7;
  WriteLn(A.Contains(P), ' ', A.Equals(B));
  B.Copy(A);
  WriteLn(A.Equals(B));
  O := New(PObject, Init);
  O^.Free;
  WriteLn('ok');
end.
