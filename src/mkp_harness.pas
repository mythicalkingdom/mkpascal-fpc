unit mkp_harness;
{ The two things a host gives an MKPascal session:
    TMKTerm   the terminal (output, line and key input, cursor, colours)
    TMKFiles  the file harness (all file access goes through it, never straight to the OS)
  plus ready-made implementations: console, buffer (for tests), disk (confined to a directory),
  memory, and deny. }
{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes;

type
  { error raised by a file harness; Code is a Node-style code: ENOENT, EEXIST, EACCES, EINVAL, ENOTDIR, EPERM }
  EMKFile = class(Exception)
  public
    Code: string;
    constructor CreateCode(const ACode, Msg: string);
  end;

  { ---- terminal ---- }
  TMKTerm = class
  private
    FPending: RawByteString;       // rest of a line handed out by the default ReadKey
  public
    { send bytes to the screen; CR LF ends a line }
    procedure Write(const S: RawByteString); virtual; abstract;
    { blocking: one line of input, without its end of line.  False when the input is closed }
    function ReadLine(out Line: RawByteString): Boolean; virtual; abstract;
    { True if ReadLine itself echoes the end of the line (a tty does); otherwise the interpreter writes CR LF }
    function LineEndEchoed: Boolean; virtual;
    { blocking: one key as a character code, or -1 when the input is closed }
    function ReadKey: Integer; virtual;
    function KeyPressed: Boolean; virtual;
    procedure ClearScreen; virtual;
    procedure GotoXY(X, Y: Integer); virtual;
    procedure GetXY(out X, Y: Integer); virtual;
    procedure SetColor(Fg, Bg: Integer); virtual;     // IBM colours 0..15 / 0..7
    procedure PrinterWrite(const S: RawByteString); virtual;   // default: not available
    procedure EndSession; virtual;
    function HasPrinter: Boolean; virtual;
    { HostCall(Cmd): a question to the program the interpreter is embedded in; the answer is text.  Err <> '' is a run-time error
      (code 300) with that text.  The default has no host. }
    function HostCall(const Cmd: RawByteString; out Err: string): RawByteString; virtual;
  end;

  { stdin / stdout }
  TConsoleTerm = class(TMKTerm)
  public
    procedure Write(const S: RawByteString); override;
    function ReadLine(out Line: RawByteString): Boolean; override;
    function LineEndEchoed: Boolean; override;
  end;

  { scripted terminal: output is collected, input comes from lines and keys given in advance }
  TBufferTerm = class(TMKTerm)
  private
    FLines: TStringList;
    FKeys: RawByteString;
    FX, FY: Integer;
  public
    Output: RawByteString;
    Printed: RawByteString;
    constructor Create;
    destructor Destroy; override;
    procedure AddLine(const S: string);
    procedure AddKeys(const S: RawByteString);
    procedure Write(const S: RawByteString); override;
    function ReadLine(out Line: RawByteString): Boolean; override;
    function ReadKey: Integer; override;
    function KeyPressed: Boolean; override;
    procedure GotoXY(X, Y: Integer); override;
    procedure GetXY(out X, Y: Integer); override;
    procedure PrinterWrite(const S: RawByteString); override;
    function HasPrinter: Boolean; override;
    function LineEndEchoed: Boolean; override;
  end;

  { ---- file harness ---- }
  TMKFiles = class
  public
    function ReadFile(const Name: string): RawByteString; virtual; abstract;
    procedure WriteFile(const Name: string; const Data: RawByteString); virtual; abstract;
    function Exists(const Name: string): Boolean; virtual; abstract;
    procedure Remove(const Name: string); virtual; abstract;
    procedure Rename(const FromName, ToName: string); virtual; abstract;
    procedure List(Names: TStrings); virtual; abstract;
    { file dates are optional: a harness that has them returns True from HasDates }
    function HasDates: Boolean; virtual;
    procedure Stat(const Name: string; out Size: Int64; out MTime: TDateTime); virtual;
    procedure SetTime(const Name: string; MTime: TDateTime); virtual;
  end;

  { refuses every operation }
  TDenyFiles = class(TMKFiles)
  public
    function ReadFile(const Name: string): RawByteString; override;
    procedure WriteFile(const Name: string; const Data: RawByteString); override;
    function Exists(const Name: string): Boolean; override;
    procedure Remove(const Name: string); override;
    procedure Rename(const FromName, ToName: string); override;
    procedure List(Names: TStrings); override;
    function HasDates: Boolean; override;
    procedure Stat(const Name: string; out Size: Int64; out MTime: TDateTime); override;
    procedure SetTime(const Name: string; MTime: TDateTime); override;
  end;

  TMKClock = function: TDateTime;

  { files held in memory; names are not case sensitive }
  TMemoryFiles = class(TMKFiles)
  private
    FNames: TStringList;     // display names; Objects[i] is a TMemFile
    function Find(const Name: string): Integer;
  public
    Clock: TMKClock;          // time given to files when written (default: Now)
    constructor Create;
    destructor Destroy; override;
    function ReadFile(const Name: string): RawByteString; override;
    procedure WriteFile(const Name: string; const Data: RawByteString); override;
    function Exists(const Name: string): Boolean; override;
    procedure Remove(const Name: string); override;
    procedure Rename(const FromName, ToName: string); override;
    procedure List(Names: TStrings); override;
    function HasDates: Boolean; override;
    procedure Stat(const Name: string; out Size: Int64; out MTime: TDateTime); override;
    procedure SetTime(const Name: string; MTime: TDateTime); override;
  end;

  { files in one directory of the disk (no sub directories, no ".." or drive letters, no symbolic links);
    names match case-insensitively when there is no exact match }
  TDiskFiles = class(TMKFiles)
  private
    FRoot: string;
    function Resolve(const Name: string; MustExist: Boolean): string;
  public
    constructor Create(const ARoot: string);
    function ReadFile(const Name: string): RawByteString; override;
    procedure WriteFile(const Name: string; const Data: RawByteString); override;
    function Exists(const Name: string): Boolean; override;
    procedure Remove(const Name: string); override;
    procedure Rename(const FromName, ToName: string); override;
    procedure List(Names: TStrings); override;
    function HasDates: Boolean; override;
    procedure Stat(const Name: string; out Size: Int64; out MTime: TDateTime); override;
    procedure SetTime(const Name: string; MTime: TDateTime); override;
  end;

implementation

uses
  BaseUnix;

{ ---------------- EMKFile ---------------- }

constructor EMKFile.CreateCode(const ACode, Msg: string);
begin
  inherited Create(Msg);
  Code := ACode;
end;

{ ---------------- TMKTerm ---------------- }

function TMKTerm.LineEndEchoed: Boolean;
begin
  Result := False;
end;

function TMKTerm.ReadKey: Integer;
var
  L: RawByteString;
begin
  { fallback for terminals that only deliver lines: hand the line out one character at a time, then a CR }
  if FPending = '' then
  begin
    if not ReadLine(L) then Exit(-1);
    FPending := L + #13;
  end;
  Result := Ord(FPending[1]);
  Delete(FPending, 1, 1);
end;

function TMKTerm.KeyPressed: Boolean;
begin
  Result := FPending <> '';
end;

procedure TMKTerm.ClearScreen;
begin
  Write(#27'[2J'#27'[H');
end;

procedure TMKTerm.GotoXY(X, Y: Integer);
begin
  Write(#27'[' + IntToStr(Y) + ';' + IntToStr(X) + 'H');
end;

procedure TMKTerm.GetXY(out X, Y: Integer);
begin
  X := 1;
  Y := 1;
end;

procedure TMKTerm.SetColor(Fg, Bg: Integer);
const
  Ansi: array[0..7] of Integer = (30, 34, 32, 36, 31, 35, 33, 37);
var
  S: string;
begin
  S := #27'[0;' + IntToStr(Ansi[Fg and 7]) + ';';
  if Fg > 7 then S := S + '1;';
  Write(S + IntToStr(Ansi[Bg and 7] + 10) + 'm');
end;

procedure TMKTerm.PrinterWrite(const S: RawByteString);
begin
  raise EMKFile.CreateCode('EPERM', 'No printer');
end;

procedure TMKTerm.EndSession;
begin
end;

function TMKTerm.HasPrinter: Boolean;
begin
  Result := False;
end;

function TMKTerm.HostCall(const Cmd: RawByteString; out Err: string): RawByteString;
begin
  Result := '';
  Err := 'there is no host to ask';
end;

{ ---------------- TConsoleTerm ---------------- }

procedure TConsoleTerm.Write(const S: RawByteString);
begin
  system.Write(Output, S);
  Flush(Output);
end;

function TConsoleTerm.ReadLine(out Line: RawByteString): Boolean;
var
  S: string;
begin
  Result := not Eof(Input);
  if Result then
  begin
    system.ReadLn(Input, S);
    Line := S;
  end
  else
    Line := '';
end;

function TConsoleTerm.LineEndEchoed: Boolean;
begin
  Result := True;           // a tty echoes the newline the user typed
end;

{ ---------------- TBufferTerm ---------------- }

constructor TBufferTerm.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
  FX := 1;
  FY := 1;
end;

destructor TBufferTerm.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

procedure TBufferTerm.AddLine(const S: string);
begin
  FLines.Add(S);
end;

procedure TBufferTerm.AddKeys(const S: RawByteString);
begin
  FKeys := FKeys + S;
end;

procedure TBufferTerm.Write(const S: RawByteString);
begin
  Output := Output + S;
end;

function TBufferTerm.ReadLine(out Line: RawByteString): Boolean;
begin
  Result := FLines.Count > 0;
  if Result then
  begin
    Line := FLines[0];
    FLines.Delete(0);
  end
  else
    Line := '';
end;

function TBufferTerm.ReadKey: Integer;
begin
  if FKeys = '' then Exit(inherited ReadKey);
  Result := Ord(FKeys[1]);
  Delete(FKeys, 1, 1);
end;

function TBufferTerm.KeyPressed: Boolean;
begin
  Result := (FKeys <> '') or inherited KeyPressed;
end;

procedure TBufferTerm.GotoXY(X, Y: Integer);
begin
  FX := X;
  FY := Y;
end;

procedure TBufferTerm.GetXY(out X, Y: Integer);
begin
  X := FX;
  Y := FY;
end;

procedure TBufferTerm.PrinterWrite(const S: RawByteString);
begin
  Printed := Printed + S;
end;

function TBufferTerm.HasPrinter: Boolean;
begin
  Result := True;
end;

function TBufferTerm.LineEndEchoed: Boolean;
begin
  Result := True;          // scripted input: nothing extra is written when a line is read
end;

{ ---------------- TMKFiles defaults ---------------- }

function TMKFiles.HasDates: Boolean;
begin
  Result := False;
end;

procedure TMKFiles.Stat(const Name: string; out Size: Int64; out MTime: TDateTime);
begin
  Size := Length(ReadFile(Name));
  MTime := 0;
end;

procedure TMKFiles.SetTime(const Name: string; MTime: TDateTime);
begin
end;

{ ---------------- TDenyFiles ---------------- }

function TDenyFiles.ReadFile(const Name: string): RawByteString;
begin
  Result := '';
  raise EMKFile.CreateCode('EPERM', 'Permission denied');
end;

procedure TDenyFiles.WriteFile(const Name: string; const Data: RawByteString);
begin
  raise EMKFile.CreateCode('EPERM', 'Permission denied');
end;

function TDenyFiles.Exists(const Name: string): Boolean;
begin
  Result := False;
  raise EMKFile.CreateCode('EPERM', 'Permission denied');
end;

procedure TDenyFiles.Remove(const Name: string);
begin
  raise EMKFile.CreateCode('EPERM', 'Permission denied');
end;

procedure TDenyFiles.Rename(const FromName, ToName: string);
begin
  raise EMKFile.CreateCode('EPERM', 'Permission denied');
end;

procedure TDenyFiles.List(Names: TStrings);
begin
  raise EMKFile.CreateCode('EPERM', 'Permission denied');
end;

function TDenyFiles.HasDates: Boolean;
begin
  Result := True;
end;

procedure TDenyFiles.Stat(const Name: string; out Size: Int64; out MTime: TDateTime);
begin
  raise EMKFile.CreateCode('EPERM', 'Permission denied');
end;

procedure TDenyFiles.SetTime(const Name: string; MTime: TDateTime);
begin
  raise EMKFile.CreateCode('EPERM', 'Permission denied');
end;

{ ---------------- TMemoryFiles ---------------- }

type
  TMemFile = class
    Data: RawByteString;
    MTime: TDateTime;
  end;

constructor TMemoryFiles.Create;
begin
  inherited Create;
  FNames := TStringList.Create;
  FNames.OwnsObjects := True;
end;

destructor TMemoryFiles.Destroy;
begin
  FNames.Free;
  inherited Destroy;
end;

function TMemoryFiles.Find(const Name: string): Integer;
var
  I: Integer;
begin
  if Name = '' then raise EMKFile.CreateCode('EINVAL', 'Bad file name');
  for I := 0 to FNames.Count - 1 do
    if SameText(FNames[I], Name) then Exit(I);
  Result := -1;
end;

function TMemoryFiles.ReadFile(const Name: string): RawByteString;
var
  I: Integer;
begin
  I := Find(Name);
  if I < 0 then raise EMKFile.CreateCode('ENOENT', 'File not found');
  Result := TMemFile(FNames.Objects[I]).Data;
end;

procedure TMemoryFiles.WriteFile(const Name: string; const Data: RawByteString);
var
  I: Integer;
  F: TMemFile;
begin
  I := Find(Name);
  if I < 0 then
  begin
    F := TMemFile.Create;
    FNames.AddObject(Name, F);
  end
  else
    F := TMemFile(FNames.Objects[I]);
  F.Data := Data;
  if Assigned(Clock) then F.MTime := Clock() else F.MTime := Now;
end;

function TMemoryFiles.Exists(const Name: string): Boolean;
begin
  Result := Find(Name) >= 0;
end;

procedure TMemoryFiles.Remove(const Name: string);
var
  I: Integer;
begin
  I := Find(Name);
  if I < 0 then raise EMKFile.CreateCode('ENOENT', 'File not found');
  FNames.Delete(I);
end;

procedure TMemoryFiles.Rename(const FromName, ToName: string);
var
  I: Integer;
begin
  I := Find(FromName);
  if I < 0 then raise EMKFile.CreateCode('ENOENT', 'File not found');
  if Find(ToName) >= 0 then raise EMKFile.CreateCode('EEXIST', 'File already exists');
  FNames[I] := ToName;
end;

procedure TMemoryFiles.List(Names: TStrings);
begin
  Names.Assign(FNames);
end;

function TMemoryFiles.HasDates: Boolean;
begin
  Result := True;
end;

procedure TMemoryFiles.Stat(const Name: string; out Size: Int64; out MTime: TDateTime);
var
  I: Integer;
begin
  I := Find(Name);
  if I < 0 then raise EMKFile.CreateCode('ENOENT', 'File not found');
  Size := Length(TMemFile(FNames.Objects[I]).Data);
  MTime := TMemFile(FNames.Objects[I]).MTime;
end;

procedure TMemoryFiles.SetTime(const Name: string; MTime: TDateTime);
var
  I: Integer;
begin
  I := Find(Name);
  if I < 0 then raise EMKFile.CreateCode('ENOENT', 'File not found');
  TMemFile(FNames.Objects[I]).MTime := MTime;
end;

{ ---------------- TDiskFiles ---------------- }

constructor TDiskFiles.Create(const ARoot: string);
begin
  inherited Create;
  FRoot := ExcludeTrailingPathDelimiter(ExpandFileName(ARoot));
end;

function IsLink(const Path: string): Boolean;
var
  St: Stat;
begin
  Result := (fpLStat(Path, St) = 0) and fpS_ISLNK(St.st_mode);
end;

function TDiskFiles.Resolve(const Name: string; MustExist: Boolean): string;
var
  Parts: TStringList;
  Cur, Part, Next, Found: string;
  I: Integer;
  SR: TSearchRec;
  S: string;
begin
  if (Name = '') or (Pos(#0, Name) > 0) then raise EMKFile.CreateCode('EINVAL', 'Bad file name');
  Parts := TStringList.Create;
  try
    S := StringReplace(Name, '\', '/', [rfReplaceAll]);
    Parts.Delimiter := '/';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := S;
    for I := Parts.Count - 1 downto 0 do
      if Parts[I] = '' then Parts.Delete(I);
    if Parts.Count = 0 then raise EMKFile.CreateCode('EINVAL', 'Bad file name');
    Cur := FRoot;
    for I := 0 to Parts.Count - 1 do
    begin
      Part := Parts[I];
      if (Part = '..') or (Part = '.') or ((Length(Part) = 2) and (Part[2] = ':')) then
        raise EMKFile.CreateCode('EACCES', 'Path not allowed');
      Next := Cur + '/' + Part;
      if not (FileExists(Next) or DirectoryExists(Next)) then
      begin
        { try a case-insensitive match in this directory }
        Found := '';
        if FindFirst(Cur + '/*', faAnyFile, SR) = 0 then
        begin
          repeat
            if SameText(SR.Name, Part) then
            begin
              Found := SR.Name;
              Break;
            end;
          until FindNext(SR) <> 0;
          FindClose(SR);
        end;
        if Found <> '' then
          Next := Cur + '/' + Found
        else if I < Parts.Count - 1 then
          raise EMKFile.CreateCode('ENOTDIR', 'Path not found');
      end;
      if IsLink(Next) then raise EMKFile.CreateCode('EACCES', 'Path not allowed');
      Cur := Next;
    end;
    Result := Cur;
  finally
    Parts.Free;
  end;
end;

function TDiskFiles.ReadFile(const Name: string): RawByteString;
var
  P: string;
  F: TFileStream;
begin
  P := Resolve(Name, True);
  if not FileExists(P) then raise EMKFile.CreateCode('ENOENT', 'File not found');
  try
    F := TFileStream.Create(P, fmOpenRead or fmShareDenyNone);
  except
    on E: Exception do raise EMKFile.CreateCode('EACCES', E.Message);
  end;
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

procedure TDiskFiles.WriteFile(const Name: string; const Data: RawByteString);
var
  P: string;
  F: TFileStream;
begin
  P := Resolve(Name, False);
  try
    F := TFileStream.Create(P, fmCreate);
  except
    on E: Exception do raise EMKFile.CreateCode('EACCES', E.Message);
  end;
  try
    if Length(Data) > 0 then F.WriteBuffer(Data[1], Length(Data));
  finally
    F.Free;
  end;
end;

function TDiskFiles.Exists(const Name: string): Boolean;
begin
  try
    Result := FileExists(Resolve(Name, False));
  except
    on EMKFile do Result := False;
  end;
end;

procedure TDiskFiles.Remove(const Name: string);
var
  P: string;
begin
  P := Resolve(Name, True);
  if not FileExists(P) then raise EMKFile.CreateCode('ENOENT', 'File not found');
  if not DeleteFile(P) then raise EMKFile.CreateCode('EACCES', 'Permission denied');
end;

procedure TDiskFiles.Rename(const FromName, ToName: string);
var
  PF, PT: string;
begin
  PF := Resolve(FromName, True);
  PT := Resolve(ToName, False);
  if not FileExists(PF) then raise EMKFile.CreateCode('ENOENT', 'File not found');
  if FileExists(PT) then raise EMKFile.CreateCode('EEXIST', 'File already exists');
  if not RenameFile(PF, PT) then raise EMKFile.CreateCode('EACCES', 'Permission denied');
end;

procedure TDiskFiles.List(Names: TStrings);
var
  SR: TSearchRec;
begin
  Names.Clear;
  if FindFirst(FRoot + '/*', faAnyFile and not faDirectory, SR) = 0 then
  begin
    repeat
      if (SR.Attr and faDirectory) = 0 then Names.Add(SR.Name);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
end;

function TDiskFiles.HasDates: Boolean;
begin
  Result := True;
end;

procedure TDiskFiles.Stat(const Name: string; out Size: Int64; out MTime: TDateTime);
var
  P: string;
  SR: TSearchRec;
begin
  P := Resolve(Name, True);
  if FindFirst(P, faAnyFile, SR) <> 0 then raise EMKFile.CreateCode('ENOENT', 'File not found');
  try
    Size := SR.Size;
    MTime := FileDateToDateTime(SR.Time);
  finally
    FindClose(SR);
  end;
end;

procedure TDiskFiles.SetTime(const Name: string; MTime: TDateTime);
var
  P: string;
begin
  P := Resolve(Name, True);
  if not FileExists(P) then raise EMKFile.CreateCode('ENOENT', 'File not found');
  FileSetDate(P, DateTimeToFileDate(MTime));
end;

end.
