program t; var a: array[1..2] of integer; function get(x: array of integer; i: integer): integer; begin get := x[i] end;
begin writeln(get(a, 1)); writeln(get(a, 2)) end.
