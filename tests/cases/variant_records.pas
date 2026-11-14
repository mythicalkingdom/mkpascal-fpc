program t;
type Rec = record kind: byte; case boolean of true: (i: integer); false: (a, b: byte) end;
var r: Rec;
begin r.kind := 1; r.i := 5; writeln(r.kind, r.i, sizeof(r)); r.a := 7; writeln(r.a, ' ', r.i) end.
