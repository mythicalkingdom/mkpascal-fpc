program t; uses Dos;
var sr: SearchRec; f: text; d: DateTime; p: longint; dir: DirStr; nm: NameStr; ex: ExtStr;
procedure show; begin UnpackTime(p, d); writeln(d.Year, '-', d.Month, '-', d.Day, ' ', d.Hour, ':', d.Min, ':', d.Sec) end;
begin
  FindFirst('*.pas', AnyFile, sr);
  while DosError = 0 do begin writeln(sr.Name, ' ', sr.Size); FindNext(sr) end;
  FSplit('C:\DIR\FILE.EXT', dir, nm, ex); writeln(dir, '|', nm, '|', ex);
  assign(f, 'old.txt'); reset(f); GetFTime(f, p); show; close(f);
  FindFirst('*.txt', AnyFile, sr); p := sr.Time; show; writeln(sr.Size);
  assign(f, 'new.txt'); rewrite(f); writeln(f, 'x'); d.Year := 1994; d.Month := 7; d.Day := 21; d.Hour := 13; d.Min := 45; d.Sec := 30;
  PackTime(d, p); SetFTime(f, p); close(f);
  reset(f); GetFTime(f, p); show; close(f);
  writeln(DosVersion > 0, ' ', length(GetEnv('PATH')), ' ', FExpand('abc'));
end.
