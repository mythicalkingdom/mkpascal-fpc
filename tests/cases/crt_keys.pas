program t;
uses Crt;
var c: char; n: integer;
begin
  ClrScr; GotoXY(3, 4); TextColor(Yellow); TextBackground(Blue); writeln(WhereX, ' ', WhereY);
  c := ReadKey; writeln(ord(c)); writeln(KeyPressed); c := ReadKey; writeln(c); writeln(KeyPressed);
end.
