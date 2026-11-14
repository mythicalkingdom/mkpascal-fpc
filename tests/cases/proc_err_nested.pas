program t; type TP = procedure; var f: TP;
procedure outer; procedure inner; begin end; begin f := @inner end;
begin outer end.
