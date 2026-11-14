program t;
var i, s: integer;
begin
  s := 0; for i := 1 to 10 do s := s + i; writeln(s);
  for i := 3 downto 1 do write(i); writeln;
  i := 0; while i < 3 do begin write(i); i := i + 1 end; writeln;
  repeat i := i - 1; write(i) until i = 0; writeln;
  if s > 50 then writeln('big') else writeln('small');
  case i of 0: writeln('zero'); 1, 2: writeln('few'); else writeln('many') end;
  for i := 1 to 10 do begin if i = 3 then continue; if i = 6 then break; write(i) end; writeln;
end.
