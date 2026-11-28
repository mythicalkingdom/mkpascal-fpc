program Hello;
var
  name: string;
  i: integer;
begin
  write('What is your name? ');
  readln(name);
  if name = '' then name := 'World';
  writeln('Hello, ', name, '!');
  writeln('  n   n*n   n*n*n');
  for i := 1 to 10 do
    writeln(i:3, i * i:6, i * i * i:8);
end.
