program t; type A = object constructor Init; procedure P; end; PA = ^A; var p: PA; constructor A.Init; begin end; procedure A.P; begin end; begin new(p, P) end.
