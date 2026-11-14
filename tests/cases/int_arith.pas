program t;
var i: integer; l: longint; b: byte; w: word;
begin
  i := 32767; i := i + 1; writeln(i);
  l := 32767; l := l + 1; writeln(l);
  b := 255; b := b + 1; writeln(b);
  w := 65535; w := w + 1; writeln(w);
  writeln(7 div 2, ' ', -7 div 2, ' ', 7 mod 3, ' ', -7 mod 3);
  writeln(40000 * 2);
  l := 100000; writeln(l * 3, ' ', l div 7);
  writeln(1 shl 4, ' ', 255 shr 4, ' ', 12 and 10, ' ', 12 or 3, ' ', 12 xor 5);
  i := -5; writeln(abs(i), ' ', sqr(i), ' ', odd(i), ' ', not 0);
end.
