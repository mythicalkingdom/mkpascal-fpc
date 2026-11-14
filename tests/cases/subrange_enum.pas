program t;
type Day = (Mon, Tue, Wed); Small = 1..5;
var d: Small; c: char;
begin
  d := 3; inc(d); writeln(d); c := 'a'; inc(c); writeln(c, ord(c), chr(100)); writeln(high(Day), ' ', low(Day) = Mon);
  writeln(ord('A'), ' ', Day(2) = Wed, ' ', succ('a'));
end.
