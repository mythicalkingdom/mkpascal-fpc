program t;
type
  TBase = object x: integer; constructor Init(a, b: integer); procedure Show; end;
  TDer = object(TBase) procedure Show; end;
constructor TBase.Init(a, b: integer); begin x := a end;
procedure TBase.Show; begin writeln('base') end;
procedure TDer.Show; begin writeln('der') end;
var b: TBase; d: TDer; bp: ^TBase;
begin b.Init(0, 0); d.Init(0, 0); b.Show; d.Show; bp := @d; bp^.Show end.
