program t;
type Pt = record x, y: integer end; Person = record name: string; pos: Pt end;
var p, q: Pt; r: Person; list: array[1..3] of Pt;
begin
  p.x := 3; p.y := 4; writeln(p.x + p.y); q := p; q.x := 10; writeln(p.x, ' ', q.x);
  with p do begin x := 1; y := 2 end; writeln(p.x, p.y);
  r.name := 'Bob'; r.pos.x := 5; with r, r.pos do writeln(name, ' ', x);
  list[2].y := 8; writeln(list[2].y);
  writeln(sizeof(Pt), ' ', sizeof(Person));
end.
