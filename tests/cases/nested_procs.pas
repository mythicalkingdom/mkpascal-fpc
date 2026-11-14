program t;
var g: integer;
procedure outer(n: integer);
  var loc: integer;
  procedure inner(k: integer);
    procedure innermost; begin loc := loc + g + k end;
  begin innermost; if k > 0 then inner(k - 1) end;
begin loc := 0; g := 100; inner(n); writeln(loc) end;
begin outer(5) end.
