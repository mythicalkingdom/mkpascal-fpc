program embed;
// How a host program (a BBS door server, a web console, a test rig...) embeds MKPascal.
// The host supplies two things: a terminal (TMKTerm) and a file harness (TMKFiles).
// Here a terminal that upper-cases the program's output and logs file access, and a file harness
// that keeps files in memory and refuses names it does not like.
{$mode objfpc}{$H+}

uses
  SysUtils, Classes, mkp_harness, mkpascal;

type
  { a terminal is just output plus input; everything else has a sensible default }
  TShoutTerm = class(TMKTerm)
  private
    FInput: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Write(const S: RawByteString); override;
    function ReadLine(out Line: RawByteString): Boolean; override;
    function LineEndEchoed: Boolean; override;
    procedure Feed(const Line: string);
  end;

  { a file harness: any storage you like behind the same seven methods }
  TLoggingFiles = class(TMemoryFiles)
  public
    function ReadFile(const Name: string): RawByteString; override;
    procedure WriteFile(const Name: string; const Data: RawByteString); override;
  end;

constructor TShoutTerm.Create;
begin
  inherited Create;
  FInput := TStringList.Create;
end;

destructor TShoutTerm.Destroy;
begin
  FInput.Free;
  inherited Destroy;
end;

procedure TShoutTerm.Feed(const Line: string);
begin
  FInput.Add(Line);
end;

procedure TShoutTerm.Write(const S: RawByteString);
begin
  System.Write(UpperCase(S));
end;

function TShoutTerm.ReadLine(out Line: RawByteString): Boolean;
begin
  Result := FInput.Count > 0;
  if Result then
  begin
    Line := FInput[0];
    FInput.Delete(0);
  end;
end;

function TShoutTerm.LineEndEchoed: Boolean;
begin
  Result := True;
end;

function TLoggingFiles.ReadFile(const Name: string): RawByteString;
begin
  System.WriteLn('[files] read ', Name);
  Result := inherited ReadFile(Name);
end;

procedure TLoggingFiles.WriteFile(const Name: string; const Data: RawByteString);
begin
  System.WriteLn('[files] write ', Name, ' (', Length(Data), ' bytes)');
  inherited WriteFile(Name, Data);
end;

const
  Source =
    'program Visitor;'#10 +
    'var name: string; f: text; line: string;'#10 +
    'begin'#10 +
    '  write(''Your name? ''); readln(name);'#10 +
    '  assign(f, ''guests.txt''); rewrite(f); writeln(f, name); close(f);'#10 +
    '  reset(f); readln(f, line); close(f);'#10 +
    '  writeln(''Saved and read back: '', line);'#10 +
    'end.'#10;

var
  Term: TShoutTerm;
  Files: TLoggingFiles;
  Session: TMKSession;
  Status: TMKRunStatus;
begin
  Term := TShoutTerm.Create;
  Files := TLoggingFiles.Create;
  Session := TMKSession.Create(Term, Files);
  try
    Term.Feed('Ada Lovelace');
    Session.MaxSteps := 1000000;                 // limits for programs you do not trust
    Session.MaxRuntimeMs := 5000;
    if not Session.LoadSource(Source) then
    begin
      System.WriteLn(Session.LastError);
      Halt(1);
    end;
    Status := Session.Run;
    System.WriteLn;
    System.WriteLn('status: ', Ord(Status), ' exit code: ', Session.ExitCode);
  finally
    Session.Free;
    Files.Free;
    Term.Free;
  end;
end.
