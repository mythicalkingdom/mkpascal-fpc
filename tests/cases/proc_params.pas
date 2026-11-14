program t;
type TP = procedure(var n: integer); TW = procedure(n: integer);
var a: integer; walk: TW;
procedure incr(var n: integer); begin n := n + 1 end;
procedure dbl(var n: integer); begin n := n * 2 end;
const tbl: array[1..2] of TP = (incr, dbl);
procedure countdown(n: integer); begin write(n, ' '); if n > 0 then walk(n - 1) end;
begin tbl[1](a); tbl[2](a); writeln(a); walk := @countdown; countdown(3); writeln end.
