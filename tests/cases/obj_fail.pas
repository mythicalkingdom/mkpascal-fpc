program t;
type
  TBase = object size: integer; constructor Init(n: integer); destructor Done; virtual; end;
  TKid = object(TBase) extra: integer; constructor Init(n, e: integer); end;
  PBase = ^TBase; PKid = ^TKid;
constructor TBase.Init(n: integer); begin if n < 0 then Fail; size := n end;
destructor TBase.Done; begin writeln('done') end;
constructor TKid.Init(n, e: integer); begin if not TBase.Init(n) then Fail; extra := e end;
var p, q, r: PBase; k: PKid; b: TBase; kid: TKid;
begin
  new(p, Init(5)); writeln(p <> nil, ' ', p^.size);
  new(q, Init(-1)); writeln(q = nil);
  r := New(PBase, Init(-2)); writeln(r = nil); r := New(PBase, Init(7)); writeln(r^.size);
  k := New(PKid, Init(3, 4)); writeln(k^.size, k^.extra); k := New(PKid, Init(-3, 4)); writeln(k = nil);
  writeln(b.Init(4), ' ', b.size); writeln(b.Init(-1)); b.Init(-5); b.Init(6); writeln(b.size);
  writeln(kid.Init(1, 2), kid.Init(-1, 2), kid.Init(2, 3), ' ', kid.extra);
  if not kid.Init(-9, 0) then writeln('failed') else writeln('ok');
end.
