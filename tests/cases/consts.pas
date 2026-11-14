program t;
type Pt = record x, y: integer end;
const Max = 10 * 2; Name = 'abc'; Tbl: array[1..3] of integer = (5, 6, 7); counter: integer = 41;
  P: Pt = (x: 1, y: 2);
begin
  writeln(Max, ' ', Name, ' ', Tbl[2], ' ', P.y); Tbl[2] := 0; writeln(Tbl[2]); counter := counter + 1; writeln(counter);
end.
