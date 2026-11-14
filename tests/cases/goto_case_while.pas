program t; label out; var x: integer; begin x := 0; while true do begin x := x + 1; case x of 1: ; 2: goto out; end end; out: writeln(x) end.
