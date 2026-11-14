program t;
var s, t, u, v: string; i: integer;
begin
  s := 'Hello'; writeln(ord(s[0]), ' ', length(s));
  s[0] := #3; writeln(s, '|', length(s));
  s[0] := #5; writeln(s);
  t := ''; for i := 1 to 4 do t[i] := chr(64 + i); writeln(length(t)); t[0] := #4; writeln(t);
  u := 'abc'; u[length(u) + 1] := 'd'; writeln(u, length(u)); u[0] := chr(length(u) + 1); writeln(u);
  FillChar(v, sizeof(v), ' '); writeln(ord(v[0]), ' ', length(v)); v[0] := #6; writeln('[', v, ']');
  FillChar(v, 256, 0); writeln(length(v));
end.
