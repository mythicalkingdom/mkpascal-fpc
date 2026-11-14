program t;
type PNode = ^TNode; TNode = record val: integer; next: PNode end;
var head, n: PNode; i: integer; ip: ^integer;
begin
  head := nil;
  for i := 1 to 3 do begin new(n); n^.val := i; n^.next := head; head := n end;
  n := head; while n <> nil do begin write(n^.val); n := n^.next end; writeln;
  while head <> nil do begin n := head; head := head^.next; dispose(n) end; writeln(head = nil);
  new(ip); ip^ := 42; writeln(ip^); ip^ := ip^ + 1; writeln(ip^);
end.
