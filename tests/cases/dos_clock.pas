program t; uses Dos;
var y, m, d, dow, h, mi, s, s100: word;
begin GetDate(y, m, d, dow); GetTime(h, mi, s, s100); writeln(y, ' ', m, ' ', d, ' ', dow, ' ', h, ':', mi, ':', s, '.', s100) end.
