program t;
type Buf = array[1..4] of byte;
var a: Buf; i: integer;
procedure zap(var x: array of byte); begin FillChar(x, high(x) + 1, 7) end;
procedure copyto(var x, y: array of byte); begin Move(x, y, high(x) + 1) end;
var b: Buf;
begin for i := 1 to 4 do a[i] := i; copyto(a, b); zap(a); for i := 1 to 4 do write(a[i], b[i], ' '); writeln end.
