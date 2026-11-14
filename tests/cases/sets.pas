program t;
var s, t, u: set of 0..20; cs: set of char;
begin
  s := [1, 3..5]; if 4 in s then writeln('in'); s := s + [9]; writeln(9 in s, 2 in s);
  include(s, 2); exclude(s, 3); writeln(2 in s, 3 in s);
  t := [1..3] * [2..5]; writeln(2 in t, 4 in t); u := [1..3] - [2]; writeln(1 in u, 2 in u);
  writeln([1, 2] <= [1, 2, 3], [1, 2] = [2, 1], 'b' in ['a'..'c']);
  cs := ['x', 'y']; if 'x' in cs then writeln('ok');
  writeln(sizeof(s), ' ', sizeof(cs));
end.
