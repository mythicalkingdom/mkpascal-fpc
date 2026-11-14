program t; uses Geom; var Count: integer;
begin Count := 1; Geom.Count := 5; writeln(Count, ' ', Geom.Count, ' ', Geom.Twice(4), ' ', Geom.Version); Geom.Bump end.
