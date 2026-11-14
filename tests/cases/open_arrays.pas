program t;
var a: array[1..3] of integer; b: array[0..1] of integer; c: array['a'..'c'] of integer; i: integer;
function sum(x: array of integer): integer; var i, s: integer; begin s := 0; for i := 0 to high(x) do s := s + x[i]; sum := s end;
procedure fill(var x: array of integer; v: integer); var i: integer; begin for i := 0 to high(x) do x[i] := v end;
function sumv(x: array of integer): integer; begin x[0] := 99; sumv := sum(x) end;
function relay(var x: array of integer): integer; begin relay := sum(x) + high(x) end;
begin
  a[1] := 1; a[2] := 2; a[3] := 3; b[0] := 10; b[1] := 20; c['a'] := 4; c['b'] := 5; c['c'] := 6;
  writeln(sum(a), ' ', sum(b), ' ', sum(c));
  fill(b, 7); writeln(b[0], b[1]);
  writeln(sumv(a), ' ', a[1]);
  writeln(relay(a), ' ', high(a), ' ', low(a));
end.
