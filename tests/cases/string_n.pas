program t;
var s: string[4]; t: string;
begin s := 'abcdefgh'; writeln(s); t := s; writeln(t, ' ', high(s)); writeln(sizeof(s), ' ', sizeof(t)) end.
