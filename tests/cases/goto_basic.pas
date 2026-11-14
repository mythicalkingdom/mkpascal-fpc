program t;
label 10, skip, again;
var i, n: integer;
begin
  i := 0; 10: i := i + 1; write(i, ' '); if i < 4 then goto 10; writeln;
  goto skip; writeln('never'); skip: writeln('after skip');
  n := 0; again: n := n + 1; if n < 3 then goto again; writeln(n);
end.
