program t;
label done;
var k: integer;
procedure find(target: integer);
label found, notfound;
var i, j: integer;
begin
  for i := 1 to 5 do for j := 1 to 5 do if i * j = target then goto found;
  goto notfound;
  found: writeln('found ', target); exit;
  notfound: writeln('no ', target)
end;
begin
  find(5); find(50);
  k := 0; repeat k := k + 1; if k = 3 then goto done; write(k, ' ') until false; done: writeln('done ', k);
end.
