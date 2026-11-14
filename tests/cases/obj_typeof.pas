program t;
type TA = object x: integer; constructor Init; procedure P; virtual; end; TB = object(TA) procedure P; virtual; end; PA = ^TA; PB = ^TB;
constructor TA.Init; begin end; procedure TA.P; begin end; procedure TB.P; begin end;
var a: TA; b: TB; ptr: PA; q: pointer;
begin
  a.Init; b.Init; writeln(TypeOf(a) = TypeOf(TA), TypeOf(b) = TypeOf(TA), TypeOf(b) = TypeOf(TB));
  ptr := New(PB, Init); writeln(TypeOf(ptr^) = TypeOf(TB), TypeOf(ptr^) = TypeOf(a)); q := TypeOf(b); writeln(q = TypeOf(TB), q <> nil);
end.
