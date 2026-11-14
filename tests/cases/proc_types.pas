program t;
type TFn = function(x: integer): integer; TProc = procedure;
var f: TFn; p: TProc; ops: array[1..2] of TFn; i: integer; saved: TFn; r: record cb: TProc end;
function square(x: integer): integer; begin square := x * x end;
function triple(x: integer): integer; begin triple := x * 3 end;
procedure hello; begin writeln('hello') end;
function apply(g: TFn; v: integer): integer; begin apply := g(v) end;
function pick(sq: boolean): TFn; begin if sq then pick := square else pick := triple end;
begin
  writeln(apply(@square, 5), ' ', apply(triple, 5)); f := square; writeln(f(6)); f := @triple; writeln(f(6));
  ops[1] := square; ops[2] := triple; for i := 1 to 2 do write(ops[i](i + 2), ' '); writeln;
  writeln(f = @triple, f = @square, f <> nil); f := nil; writeln(f = nil);
  p := hello; p; p := @hello; p(); r.cb := hello; r.cb; saved := pick(true); writeln(saved(7));
end.
