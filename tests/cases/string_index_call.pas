program t;
type TObj = object constructor Init; function Kind: string; end;
function nm: string; begin nm := 'hello' end;
constructor TObj.Init; begin end;
function TObj.Kind: string; begin Kind := 'gadget' end;
var o: TObj; c: char;
begin
  o.Init; c := nm[1]; writeln(c, nm[5], ord(nm[0]), o.Kind[1], o.Kind[6]);
  with o do writeln(Kind[2])
end.
