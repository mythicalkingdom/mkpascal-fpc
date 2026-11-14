program t;
var s: string;
function rev(s: string): string; var i: integer; r: string; begin r := ''; for i := length(s) downto 1 do r := r + s[i]; rev := r end;
function pad(s: string; n: integer): string; begin while length(s) < n do s := s + '.'; pad := s end;
begin
  s := rev('hello'); writeln(s); writeln(chr(65), chr(66)); writeln(rev('ab') + '!');
  writeln(pad('x', 4), '|', pad('long', 2), '|', length(pad('', 3)));
  writeln(upcase('q'), lowercase('MiXed'), uppercase('Mixed'));
  writeln(copy('abcdef', 3, 2), copy('abc', 5, 1), '|', copy('abc', 0, 2), '|', pos('', 'abc'));
end.
