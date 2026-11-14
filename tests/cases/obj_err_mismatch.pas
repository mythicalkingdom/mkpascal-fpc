program t; type A = object x: integer; end; B = object(A) y: integer; end; var s: A; c: B; begin c := s end.
