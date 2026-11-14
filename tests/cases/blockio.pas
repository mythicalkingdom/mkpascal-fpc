program t;
type Rec = record a: integer; b: string[2]; c: real end;
var f: file; r, r2: Rec; buf: array[1..10] of byte; i, got: integer; w: word;
begin
  assign(f, 'blk.dat'); rewrite(f, 1);
  r.a := 258; r.b := 'AB'; r.c := 1.0; BlockWrite(f, r, sizeof(r)); writeln(sizeof(r));
  for i := 1 to 10 do buf[i] := i; BlockWrite(f, buf, 10); close(f);
  reset(f, 1); writeln(filesize(f));
  BlockRead(f, r2, sizeof(r2), got); writeln(got, ' ', r2.a, r2.b, r2.c:0:1);
  BlockRead(f, buf[3], 20, got); writeln(got, ' ', buf[3], buf[4], buf[10]);
  writeln(eof(f)); close(f);
  reset(f, 1); BlockRead(f, w, 2); writeln(w);
end.
