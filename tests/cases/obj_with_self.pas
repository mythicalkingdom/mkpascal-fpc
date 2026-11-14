program t;
type
  TC = object
    x, y: integer;
    constructor Init(a, b: integer);
    procedure Move(dx, dy: integer);
    function Twice(n: integer): integer;
    function Sum: integer;
  end;
constructor TC.Init(a, b: integer); begin Self.x := a; y := b end;
procedure TC.Move(dx, dy: integer); begin x := x + dx; y := y + dy end;
function TC.Twice(n: integer): integer; begin Twice := n * 2 + Sum - Sum end;
function TC.Sum: integer; begin Sum := x + y end;
var c: TC;
begin c.Init(1, 2); with c do begin Move(1, 1); writeln(x, y, Twice(x)) end; writeln(c.Twice(4)) end.
