program t;
type Rec = record n: integer; s: string[3] end;
var a, b, c: integer; s1, s2: string[5]; buf: array[1..8] of byte; r, r2: Rec; f: file; i: integer;
procedure swap(var x, y; size: word); var t: array[1..16] of byte; begin Move(x, t, size); Move(y, x, size); Move(t, y, size) end;
procedure zap(var x; n: word); begin FillChar(x, n, 0) end;
procedure save(var f: file; var x; n: word); begin BlockWrite(f, x, n) end;
procedure load(var f: file; var x; n: word); begin BlockRead(f, x, n) end;
begin
  a := 1; b := 2; swap(a, b, sizeof(a)); writeln(a, ' ', b);
  s1 := 'abc'; s2 := 'xyz'; swap(s1, s2, sizeof(s1)); writeln(s1, ' ', s2);
  for i := 1 to 8 do buf[i] := i; zap(buf[3], 4); for i := 1 to 8 do write(buf[i]); writeln;
  r.n := 7; r.s := 'hi'; zap(r.s[1], 2); writeln(r.n, length(r.s), ord(r.s[1]));
end.
