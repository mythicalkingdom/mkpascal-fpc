program t; uses Geom; var a, b: TPoint; bx: TBox;
begin writeln('main'); a.x := 1; a.y := 2; b.x := 4; b.y := 6; writeln(Dist(a, b), ' ', Twice(Version));
  Bump; Bump; writeln(Count); bx.Init(0, 0, 5, 5); writeln(bx.Width) end.
