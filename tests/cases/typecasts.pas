program t;
type WordRec = record Lo, Hi: word end; Pair = array[0..1] of byte;
var n: longint; w: word; b: byte; c: char;
begin
  n := $12ABCDEF; writeln(WordRec(n).Hi, ' ', WordRec(n).Lo); w := $0102; writeln(Pair(w)[0], Pair(w)[1]);
  WordRec(n).Lo := 1; writeln(n);
  b := 65; c := char(b); writeln(c, byte(c), boolean(1), integer(true));
  writeln(longint(WordRec(n)) = n);
end.
