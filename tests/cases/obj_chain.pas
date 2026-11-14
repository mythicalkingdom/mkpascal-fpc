program t;
type
  A = object constructor Init; procedure Run; virtual; procedure Hello; end;
  B = object(A) procedure Run; virtual; end;
  C = object(B) procedure Run; virtual; end;
constructor A.Init; begin end;
procedure A.Hello; begin write('A') end;
procedure A.Run; begin write('a') end;
procedure B.Run; begin inherited Run; write('b') end;
procedure C.Run; begin inherited; write('c'); Hello; writeln end;
var obj: C;
begin obj.Init; obj.Run end.
