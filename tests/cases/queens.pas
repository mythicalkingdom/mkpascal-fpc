program queens;
const N = 6;
var col: array[1..N] of boolean; d1: array[2..2*N] of boolean; d2: array[-N..N] of boolean;
    pos: array[1..N] of integer; count: integer; i: integer;
procedure place(r: integer);
var c: integer;
begin
  if r > N then count := count + 1
  else for c := 1 to N do
    if col[c] and d1[r + c] and d2[r - c] then begin
      col[c] := false; d1[r + c] := false; d2[r - c] := false; pos[r] := c;
      place(r + 1);
      col[c] := true; d1[r + c] := true; d2[r - c] := true
    end
end;
begin
  for i := 1 to N do col[i] := true;
  for i := 2 to 2 * N do d1[i] := true;
  for i := -N to N do d2[i] := true;
  count := 0; place(1); writeln(count)
end.
