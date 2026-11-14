program t;
{$DEFINE FANCY}
begin
{$IFDEF MSDOS} writeln('dos'); {$ENDIF}
{$IFNDEF FANCY} writeln('plain'); {$ELSE} writeln('fancy'); {$ENDIF}
{$IFDEF NOPE} {$IFDEF FANCY} writeln('inner'); {$ELSE} writeln('x'); {$ENDIF} writeln('outer'); {$ELSE} writeln('skipped both'); {$ENDIF}
{$UNDEF FANCY}{$IFDEF FANCY} writeln('still'); {$ENDIF}
{$IFOPT R+} writeln('range on'); {$ELSE} writeln('range off'); {$ENDIF}{$R+}{$IFOPT R+} writeln('range on'); {$ENDIF}
end.
