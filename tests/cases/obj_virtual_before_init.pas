program t;
type T = object x: integer; constructor Init; procedure P; virtual; end;
constructor T.Init; begin end; procedure T.P; begin writeln('p') end;
var o: T;
begin o.P end.
