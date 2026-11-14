program t; type TF = function(x: integer): integer; var f: TF;
procedure p(y: integer); begin end;
begin f := @p end.
