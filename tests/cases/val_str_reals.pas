program t;
var r: real; n: integer; code: integer; s: string; l: longint;
begin
  val('3.25', r, code); writeln(r:0:2, ' ', code);
  val('1e3', r, code); writeln(r:0:1, ' ', code);
  val('12x', n, code); writeln(n, ' ', code);
  val('$FF', n, code); writeln(n, ' ', code);
  val('-42', l, code); writeln(l, ' ', code);
  val('', n, code); writeln(code);
  str(-17, s); writeln('[', s, ']'); str(l:6, s); writeln('[', s, ']'); str(2.5:8:3, s); writeln('[', s, ']');
  str(1.5, s); writeln('[', s, ']');
end.
