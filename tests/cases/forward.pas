program t;
function odd2(n: integer): boolean; forward;
function even(n: integer): boolean; begin if n = 0 then even := true else even := odd2(n - 1) end;
function odd2(n: integer): boolean; begin if n = 0 then odd2 := false else odd2 := even(n - 1) end;
begin writeln(even(10), ' ', odd2(7)) end.
