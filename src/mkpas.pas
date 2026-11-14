program mkpas;
// Run a Pascal program on the console:  mkpas program.pas [parameters]
// Units, include files and data files are read from (and written to) the program's directory.
{$mode objfpc}{$H+}

uses
  SysUtils, Classes, mkp_harness, mkpascal;

var
  Term: TConsoleTerm;
  Files: TDiskFiles;
  Session: TMKSession;
  Path: string;
  I: Integer;
  Status: TMKRunStatus;
begin
  if ParamCount < 1 then
  begin
    WriteLn('usage: mkpas program.pas [parameters]');
    Halt(2);
  end;
  Path := ExpandFileName(ParamStr(1));
  Term := TConsoleTerm.Create;
  Files := TDiskFiles.Create(ExtractFilePath(Path));
  Session := TMKSession.Create(Term, Files);
  try
    for I := 2 to ParamCount do Session.Params.Add(ParamStr(I));
    if not Session.LoadFile(ExtractFileName(Path)) then
    begin
      WriteLn(Session.LastError);
      Halt(1);
    end;
    Status := Session.Run;
    if Status in [rsEnd] then Halt(0) else Halt(Session.ExitCode);
  finally
    Session.Free;
    Files.Free;
    Term.Free;
  end;
end.
