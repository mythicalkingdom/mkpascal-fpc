program t;
type Vec = array[1..3] of integer; Rec = record a: integer; s: string[5] end;
var v: Vec; r: Rec;
procedure change(x: Vec; y: Rec; z: string); begin x[1] := 99; y.a := 99; y.s := 'chg'; z := 'zzz' end;
procedure bump(var x: Vec; var y: Rec); begin x[1] := x[1] + 1; y.a := y.a + 1; y.s := y.s + '!' end;
function make(n: integer): Rec; var t: Rec; begin t.a := n; t.s := 'made'; make := t end;
function sum(x: Vec): integer; var i, s: integer; begin s := 0; for i := 1 to 3 do s := s + x[i]; sum := s end;
begin
  v[1] := 1; v[2] := 2; v[3] := 3; r.a := 5; r.s := 'orig';
  change(v, r, 'abc'); writeln(v[1], r.a, r.s);
  bump(v, r); writeln(v[1], r.a, r.s);
  r := make(7); writeln(r.a, r.s, ' ', make(8).a + make(9).a, ' ', sum(v));
end.
