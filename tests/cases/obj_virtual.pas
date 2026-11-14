program t;
type
  TShape = object
    x, y: integer;
    constructor Init(ax, ay: integer);
    procedure Describe; virtual;
    procedure Move(dx, dy: integer);
    function Name: string; virtual;
    function Area: real; virtual;
    destructor Done; virtual;
  end;
  PShape = ^TShape;
  TCircle = object(TShape)
    r: integer;
    constructor Init(ax, ay, ar: integer);
    function Name: string; virtual;
    function Area: real; virtual;
  end;
  PCircle = ^TCircle;
  TSquare = object(TShape)
    side: integer;
    constructor Init(ax, ay, s: integer);
    function Name: string; virtual;
    function Area: real; virtual;
    procedure Describe; virtual;
  end;
  PSquare = ^TSquare;
var list: array[1..3] of PShape; i: integer;
constructor TShape.Init(ax, ay: integer); begin x := ax; y := ay end;
procedure TShape.Describe; begin writeln(Name, ' at ', x, ',', y, ' area ', Area:0:1) end;
procedure TShape.Move(dx, dy: integer); begin x := x + dx; y := y + dy end;
function TShape.Name: string; begin Name := 'shape' end;
function TShape.Area: real; begin Area := 0 end;
destructor TShape.Done; begin writeln('done ', Name) end;
constructor TCircle.Init(ax, ay, ar: integer); begin inherited Init(ax, ay); r := ar end;
function TCircle.Name: string; begin Result := 'circle' end;
function TCircle.Area: real; begin Area := 3 * r * r end;
constructor TSquare.Init(ax, ay, s: integer); begin inherited Init(ax, ay); side := s end;
function TSquare.Name: string; begin Name := 'square' end;
function TSquare.Area: real; begin Area := side * side end;
procedure TSquare.Describe; begin write('[sq] '); inherited Describe end;
begin
  list[1] := New(PCircle, Init(0, 0, 3)); list[2] := New(PSquare, Init(1, 1, 4)); new(list[3], Init(2, 2));
  for i := 1 to 3 do list[i]^.Describe;
  for i := 1 to 3 do dispose(list[i], Done);
end.
