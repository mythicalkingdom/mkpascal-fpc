program t;
type Color = (Red, Green, Blue);
var c: char; d: Color;
begin
  c := 'q'; case c of 'a'..'m': writeln('first'); 'n'..'z': writeln('second') end;
  d := Green; case d of Red: writeln('r'); Green, Blue: writeln('gb') end;
  writeln(ord(d), ' ', succ(d) = Blue, ' ', pred(Blue) = Green, ' ', d, ' ', high(Color));
end.
