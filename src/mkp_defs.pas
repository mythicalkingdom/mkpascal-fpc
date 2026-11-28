{ SPDX-License-Identifier: GPL-3.0-or-later }
unit mkp_defs;
{ shared exceptions and runtime error texts }
{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  { a compile error: Line/Col in FileName (an include file) or in unit InUnit }
  EMKCompile = class(Exception)
  public
    Line, Col: Integer;
    FileName: string;     // include file the error is in ('' for the main source)
    InUnit: string;       // unit the error is in ('' for the program)
    constructor CreateAt(const Msg: string; ALine, ACol: Integer; const AFile: string = '');
  end;

  { a Turbo Pascal runtime error (200 division by zero, 201 range check, ...) }
  EMKRuntime = class(Exception)
  public
    Code: Integer;
    constructor CreateCode(ACode: Integer);
  end;

  EMKHalt = class(Exception)
  public
    Code: Integer;
    constructor CreateCode(ACode: Integer);
  end;

  { a resource limit was hit; ends the program, not trappable }
  EMKLimit = class(Exception);

  { the host asked the program to stop (RequestBreak) }
  EMKBreak = class(Exception);

function RuntimeMessage(Code: Integer): string;

implementation

constructor EMKCompile.CreateAt(const Msg: string; ALine, ACol: Integer; const AFile: string);
begin
  inherited Create(Msg);
  Line := ALine;
  Col := ACol;
  FileName := AFile;
end;

constructor EMKRuntime.CreateCode(ACode: Integer);
begin
  inherited Create(RuntimeMessage(ACode));
  Code := ACode;
end;

constructor EMKHalt.CreateCode(ACode: Integer);
begin
  inherited Create('Halt');
  Code := ACode;
end;

function RuntimeMessage(Code: Integer): string;
begin
  case Code of
    2: Result := 'File not found';
    3: Result := 'Path not found';
    4: Result := 'Too many open files';
    5: Result := 'File access denied';
    100: Result := 'Disk read error';
    101: Result := 'Disk write error';
    102: Result := 'File not assigned';
    103: Result := 'File not open';
    104: Result := 'File not open for input';
    105: Result := 'File not open for output';
    106: Result := 'Invalid numeric format';
    200: Result := 'Division by zero';
    201: Result := 'Range check error';
    202: Result := 'Stack overflow error';
    203: Result := 'Heap overflow error';
    204: Result := 'Invalid pointer operation';
    205: Result := 'Floating point overflow';
    207: Result := 'Invalid floating point operation';
  else
    Result := 'Error ' + IntToStr(Code);
  end;
end;

end.
