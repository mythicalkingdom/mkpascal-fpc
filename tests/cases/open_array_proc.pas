program t;
type TFold = function(x: array of integer): integer;
var a: array[1..4] of integer; f: TFold; i: integer;
function sum(x: array of integer): integer; var i, s: integer; begin s := 0; for i := 0 to high(x) do s := s + x[i]; sum := s end;
function maxi(x: array of integer): integer; var i, m: integer; begin m := x[0]; for i := 1 to high(x) do if x[i] > m then m := x[i]; maxi := m end;
begin for i := 1 to 4 do a[i] := i * i; f := sum; writeln(f(a)); f := @maxi; writeln(f(a)) end.
