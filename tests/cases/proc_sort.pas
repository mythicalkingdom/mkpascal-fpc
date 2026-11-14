program t;
type TCmp = function(a, b: integer): boolean; TArr = array[1..6] of integer;
var v: TArr; i: integer;
function less(a, b: integer): boolean; begin less := a < b end;
function greater(a, b: integer): boolean; begin greater := a > b end;
procedure sort(var x: TArr; before: TCmp);
var i, j, t: integer;
begin
  for i := 2 to 6 do begin t := x[i]; j := i - 1; while (j >= 1) and before(t, x[j]) do begin x[j + 1] := x[j]; dec(j) end; x[j + 1] := t end
end;
begin
  v[1] := 5; v[2] := 3; v[3] := 9; v[4] := 1; v[5] := 7; v[6] := 2;
  sort(v, less); for i := 1 to 6 do write(v[i], ' '); writeln;
  sort(v, @greater); for i := 1 to 6 do write(v[i], ' '); writeln;
end.
