program t;
var a, b: array[1..5] of integer; m: array[0..2, 0..3] of integer; i, j: integer; c: array['a'..'z'] of byte;
begin
  for i := 1 to 5 do a[i] := i * i; writeln(a[3], ' ', a[5]);
  b := a; b[1] := 99; writeln(a[1], ' ', b[1]);
  for i := 0 to 2 do for j := 0 to 3 do m[i, j] := i * 10 + j; writeln(m[2, 3], ' ', m[1][2]);
  writeln(low(a), ' ', high(a), ' ', sizeof(a));
  c['b'] := 7; writeln(c['b']);
end.
