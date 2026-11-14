program t;
type Rec = record id: integer; name: string[10]; price: real end;
var f: file of Rec; g: file of integer; r: Rec; i: integer;
begin
  assign(f, 'rec.dat'); rewrite(f);
  for i := 1 to 3 do begin r.id := i; r.name := 'item' + chr(48 + i); r.price := i * 1.5; write(f, r) end;
  writeln(filesize(f), ' ', filepos(f)); close(f);
  reset(f); seek(f, 2); read(f, r); writeln(r.id, r.name, r.price:0:1, ' ', filepos(f), eof(f));
  seek(f, 0); read(f, r); r.name := 'CHANGED'; seek(f, 0); write(f, r); close(f);
  reset(f); read(f, r); writeln(r.name); close(f);
  assign(g, 'n.dat'); rewrite(g); for i := 1 to 5 do write(g, i * 1000); close(g);
  reset(g); seek(g, 4); read(g, i); writeln(i, ' ', filesize(g));
  writeln(sizeof(Rec));
end.
