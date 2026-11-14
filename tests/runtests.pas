program runtests;
// Runs every tests/cases/NAME.pas and compares the output with NAME.out.
//   NAME.in   (optional) lines of input for ReadLn
//   NAME.keys (optional) keys for ReadKey
//   NAME.UnitName.pu  source of a unit the program uses;  NAME.f.FILE  a file in the program's file harness
//   NAME.out  expected output with LF line ends.  A first line "!compile TEXT" expects a compile error containing TEXT.
{$mode objfpc}{$H+}

uses
  SysUtils, Classes, DateUtils, mkp_harness, mkpascal;

function ReadAll(const Path: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

function Norm(const S: string): string;
begin
  Result := StringReplace(S, #13#10, #10, [rfReplaceAll]);
end;

function FixedClock: TDateTime;
begin
  Result := EncodeDate(2005, 12, 24) + EncodeTime(18, 30, 40, 0);
end;

procedure LoadExtras(const Dir, Base: string; Session: TMKSession; Files: TMemoryFiles);
// NAME.UnitName.pu are unit sources, NAME.f.FILE are files the program finds in its harness
var
  SR: TSearchRec;
  Rest: string;
  Sorted: TStringList;
  I: Integer;
begin
  Sorted := TStringList.Create;
  try
    Sorted.Sorted := True;
    if FindFirst(IncludeTrailingPathDelimiter(Dir) + Base + '.*', faAnyFile, SR) = 0 then
    begin
      repeat Sorted.Add(SR.Name); until FindNext(SR) <> 0;
      FindClose(SR);
    end;
    for I := 0 to Sorted.Count - 1 do
    begin
      Rest := Copy(Sorted[I], Length(Base) + 2, MaxInt);
      if (Length(Rest) > 3) and (Copy(Rest, Length(Rest) - 2, 3) = '.pu') then
        Session.AddUnit(Copy(Rest, 1, Length(Rest) - 3), ReadAll(IncludeTrailingPathDelimiter(Dir) + Sorted[I]))
      else if Copy(Rest, 1, 2) = 'f.' then
        Files.WriteFile(Copy(Rest, 3, MaxInt), ReadAll(IncludeTrailingPathDelimiter(Dir) + Sorted[I]));
    end;
  finally
    Sorted.Free;
  end;
end;

function RunCase(const Dir, Base, Only: string): Boolean;
var
  Src, Expected, Actual, Err, Want: string;
  Term: TBufferTerm;
  Files: TMemoryFiles;
  Session: TMKSession;
  Lines: TStringList;
  I: Integer;
  P: string;
begin
  Result := False;
  P := IncludeTrailingPathDelimiter(Dir) + Base;
  Src := ReadAll(P + '.pas');
  Expected := '';
  if FileExists(P + '.out') then Expected := Norm(ReadAll(P + '.out'));
  Term := TBufferTerm.Create;
  Files := TMemoryFiles.Create;
  Session := TMKSession.Create(Term, Files);
  Lines := TStringList.Create;
  try
    Files.Clock := @FixedClock;
    Session.Clock := @FixedClock;
    LoadExtras(Dir, Base, Session, Files);
    if FileExists(P + '.in') then
    begin
      Lines.LoadFromFile(P + '.in');
      for I := 0 to Lines.Count - 1 do Term.AddLine(Lines[I]);
    end;
    if FileExists(P + '.keys') then Term.AddKeys(ReadAll(P + '.keys'));
    if Copy(Expected, 1, 9) = '!compile ' then
    begin
      Want := Trim(Copy(Expected, 10, MaxInt));
      if Session.LoadSource(Src) then
        WriteLn('FAIL ', Base, ': expected compile error "', Want, '" but it compiled')
      else
      begin
        Err := Session.LastError;
        Result := Pos(Want, Err) > 0;
        if not Result then WriteLn('FAIL ', Base, ': expected compile error "', Want, '" but got: ', Err);
      end;
      Exit;
    end;
    if not Session.LoadSource(Src) then
    begin
      WriteLn('FAIL ', Base, ': ', Session.LastError);
      Exit;
    end;
    Session.Run;
    Actual := Norm(Term.Output);
    Result := Actual = Expected;
    if not Result then
    begin
      WriteLn('FAIL ', Base, ':');
      WriteLn('  expected: ', StringReplace(Expected, #10, '\n', [rfReplaceAll]));
      WriteLn('  actual:   ', StringReplace(Actual, #10, '\n', [rfReplaceAll]));
    end;
  finally
    Lines.Free;
    Session.Free;
    Files.Free;
    Term.Free;
  end;
end;

var
  Dir, Only: string;
  SR: TSearchRec;
  Names: TStringList;
  I, Pass, Fail: Integer;
begin
  Dir := 'tests/cases';
  Only := '';
  if ParamCount >= 1 then Dir := ParamStr(1);
  if ParamCount >= 2 then Only := ParamStr(2);
  Names := TStringList.Create;
  Names.Sorted := True;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*.pas', faAnyFile, SR) = 0 then
  begin
    repeat
      if Pos('.', ChangeFileExt(SR.Name, '')) = 0 then Names.Add(ChangeFileExt(SR.Name, ''));
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  Pass := 0;
  Fail := 0;
  for I := 0 to Names.Count - 1 do
  begin
    if (Only <> '') and (Names[I] <> Only) then Continue;
    if RunCase(Dir, Names[I], Only) then Inc(Pass) else Inc(Fail);
  end;
  WriteLn(Pass, ' passed, ', Fail, ' failed');
  Names.Free;
  if Fail > 0 then Halt(1);
end.
