program t;
function depth(n: integer): integer; begin if n = 0 then depth := 0 else depth := 1 + depth(n - 1) end;
begin writeln(depth(5000)) end.
