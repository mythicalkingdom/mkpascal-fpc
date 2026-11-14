program t;
var f: text; e: integer; s: string;
begin
  assign(f, 'nope.txt');
  {$I-} reset(f); e := ioresult; {$I+}
  writeln(e, ' ', ioresult);
  readln(f, s);
end.
