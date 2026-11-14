program t; uses U; var h: PNode; begin h := NewNode(Blue, NewNode(Red, nil)); while h <> nil do begin write(Names[h^.c], ' '); h := h^.next end; writeln(Limit) end.
