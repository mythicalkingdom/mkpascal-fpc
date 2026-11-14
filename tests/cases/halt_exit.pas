program t;
procedure p; begin writeln('in'); exit; writeln('never') end;
begin p; writeln('after'); halt(3); writeln('b') end.
