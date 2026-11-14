program t;
var f, g: text; s: string; a: integer; x: real;
begin
  assign(f, 'a.txt'); rewrite(f); writeln(f, 'line one'); writeln(f, 12, ' ', 3.5:0:1); write(f, 'tail'); close(f);
  assign(g, 'a.txt'); reset(g); while not eof(g) do begin readln(g, s); writeln('[', s, ']') end; close(g);
  reset(g); readln(g, s); read(g, a, x); writeln(a, ' ', x:0:1, ' ', eoln(g)); readln(g); readln(g, s); writeln(s, eof(g)); close(g);
end.
