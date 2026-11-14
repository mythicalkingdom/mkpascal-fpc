program t;
type PRec = ^Rec; Rec = record a, b: integer; name: string[8] end; PArr = ^TArr; TArr = array[0..9] of integer;
var p, q: PRec; arr: PArr; i, sum: integer;
begin
  new(p); p^.a := 1; p^.b := 2; p^.name := 'node'; q := p; q^.a := 10; writeln(p^.a, p^.b, p^.name);
  getmem(arr, sizeof(TArr)); for i := 0 to 9 do arr^[i] := i * i; sum := 0; for i := 0 to 9 do sum := sum + arr^[i]; writeln(sum);
  freemem(arr, sizeof(TArr)); dispose(p);
  writeln(p = q, assigned(p), assigned(nil));
end.
