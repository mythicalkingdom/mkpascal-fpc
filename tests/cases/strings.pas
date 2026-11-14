program t;
var s, t, u: string; n, code: integer; c: char;
begin
  s := 'Hello'; t := s + ', ' + 'World'; writeln(t, ' ', length(t));
  writeln(copy(t, 8, 5), '|', pos('World', t), '|', pos('x', t));
  insert('big ', t, 8); writeln(t); delete(t, 8, 4); writeln(t);
  writeln(upcase('a'), ' ', s[1], s[5], ' ', concat('a', 'b', 'c'));
  s[1] := 'J'; writeln(s); writeln(s < t, ' ', s = 'Jello', ' ', 'abc' > 'abd');
  str(123, u); writeln(u, '|'); str(3.5:6:2, u); writeln(u, '|');
  val('456', n, code); writeln(n, ' ', code); val('4x6', n, code); writeln(code);
  c := 'x'; u := c + c; writeln(u);
end.
