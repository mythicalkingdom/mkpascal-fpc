program t; uses Dos;
var d, e: DateTime; p: longint;
begin
  d.Year := 1994; d.Month := 7; d.Day := 21; d.Hour := 13; d.Min := 45; d.Sec := 30;
  PackTime(d, p); writeln(p); UnpackTime(p, e);
  writeln(e.Year, '-', e.Month, '-', e.Day, ' ', e.Hour, ':', e.Min, ':', e.Sec);
  d.Year := 2107; d.Month := 12; d.Day := 31; d.Hour := 23; d.Min := 59; d.Sec := 58; PackTime(d, p); writeln(p < 0); UnpackTime(p, e); writeln(e.Year, ' ', e.Sec);
  writeln(sizeof(DateTime), ' ', sizeof(SearchRec));
end.
