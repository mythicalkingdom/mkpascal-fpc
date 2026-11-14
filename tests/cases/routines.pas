program t;
var a, b: integer;
function fact(n: longint): longint; begin if n <= 1 then fact := 1 else fact := n * fact(n - 1) end;
function fib(n: integer): integer; begin if n < 2 then Result := n else Result := fib(n-1) + fib(n-2) end;
procedure swap(var x, y: integer); var t: integer; begin t := x; x := y; y := t end;
procedure hello; begin writeln('hello') end;
begin
  writeln(fact(10)); a := 1; b := 2; swap(a, b); writeln(a, ' ', b); writeln(fib(15)); hello;
end.
