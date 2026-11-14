program t;
type Rc = record f: integer end;
var x: integer; q: ^integer; a: array[1..3] of integer; r: Rc;
procedure inc2(var v: integer); begin v := v + 2 end;
begin q := @x; q^ := 7; writeln(x); inc2(a[2]); inc2(r.f); writeln(a[2], r.f) end.
