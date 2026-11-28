{ SPDX-License-Identifier: GPL-3.0-or-later }
unit mkp_lexer;
// Tokenizer: comments, compiler directives (include files, conditional compilation, switches such as
// the range check switch), numbers, strings, symbols.  All tokens are produced up front.
{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, mkp_defs;

type
  TTokKind = (tkEOF, tkIdent, tkKeyword, tkInt, tkReal, tkString, tkSym);

  TToken = record
    Kind: TTokKind;
    Text: string;          // identifier as written, string literal contents
    Key: string;           // lower case: identifiers, keywords and symbols
    IntVal: Int64;
    RealVal: Double;
    Line, Col: Integer;
    FileIdx: Integer;      // index into TLexer.Files; 0 is the main source
    Sw: LongWord;          // compiler switches in force: bit 0 = A ... bit 25 = Z
  end;

  TIncludeFunc = function(const Name: string; out Text: string): Boolean of object;

  TLexer = class
  private
    FInclude: TIncludeFunc;
    FDefines: TStringList;
    FCond: array of record
      ParentActive, Taken, Active: Boolean;
      Line, FileIdx: Integer;
    end;
    FCondCount: Integer;
    FSw: LongWord;
    function Skipping: Boolean;
    procedure Push(const T: TToken);
    procedure Scan(const Src: string; FileIdx, Depth: Integer);
    procedure Directive(const Text: string; L, C, FileIdx, Depth: Integer);
  public
    Toks: array of TToken;
    Count: Integer;
    Files: TStringList;       // Files[0] = '' (main), then include file names
    constructor Create(AInclude: TIncludeFunc; ExtraDefines: TStrings);
    destructor Destroy; override;
    procedure Tokenize(const Src: string);
  end;

function SwBit(C: Char): LongWord;
function IsKeyword(const S: string): Boolean;

implementation

const
  KeywordList: array[0..49] of string = (
    'and', 'array', 'asm', 'begin', 'case', 'const', 'constructor', 'destructor', 'div', 'do',
    'downto', 'else', 'end', 'file', 'for', 'function', 'goto', 'if', 'implementation', 'in',
    'inherited', 'inline', 'interface', 'label', 'mod', 'nil', 'not', 'object', 'of', 'or',
    'packed', 'procedure', 'program', 'record', 'repeat', 'set', 'shl', 'shr', 'string', 'then',
    'to', 'type', 'unit', 'until', 'uses', 'var', 'while', 'with', 'xor', 'forward_');

var
  KeywordSet: TStringList;

function IsKeyword(const S: string): Boolean;
var
  Dummy: Integer;
begin
  Result := KeywordSet.Find(S, Dummy);
end;

function SwBit(C: Char): LongWord;
begin
  C := UpCase(C);
  if C in ['A'..'Z'] then Result := LongWord(1) shl (Ord(C) - Ord('A')) else Result := 0;
end;

function IsDigit(C: Char): Boolean; inline;
begin
  Result := C in ['0'..'9'];
end;

function IsHex(C: Char): Boolean; inline;
begin
  Result := C in ['0'..'9', 'a'..'f', 'A'..'F'];
end;

function IsAlpha(C: Char): Boolean; inline;
begin
  Result := C in ['a'..'z', 'A'..'Z', '_'];
end;

const
  { default state of the compiler switches: I V S D L X on }
  DefaultSwitches = (1 shl 8) or (1 shl 21) or (1 shl 18) or (1 shl 3) or (1 shl 11) or (1 shl 23);

constructor TLexer.Create(AInclude: TIncludeFunc; ExtraDefines: TStrings);
var
  I: Integer;
begin
  inherited Create;
  FInclude := AInclude;
  FDefines := TStringList.Create;
  FDefines.CaseSensitive := False;
  FDefines.Sorted := True;
  FDefines.Duplicates := dupIgnore;
  FDefines.Add('MSDOS');
  FDefines.Add('CPU86');
  FDefines.Add('VER70');
  FDefines.Add('FPC_NOT');       // placeholder removed below
  FDefines.Delete(FDefines.IndexOf('FPC_NOT'));
  if ExtraDefines <> nil then
    for I := 0 to ExtraDefines.Count - 1 do FDefines.Add(ExtraDefines[I]);
  Files := TStringList.Create;
  Files.Add('');
  FSw := DefaultSwitches;
end;

destructor TLexer.Destroy;
begin
  FDefines.Free;
  Files.Free;
  inherited Destroy;
end;

function TLexer.Skipping: Boolean;
begin
  Result := (FCondCount > 0) and not FCond[FCondCount - 1].Active;
end;

procedure TLexer.Push(const T: TToken);
begin
  if Count >= Length(Toks) then SetLength(Toks, Length(Toks) * 2 + 256);
  Toks[Count] := T;
  Inc(Count);
end;

procedure TLexer.Directive(const Text: string; L, C, FileIdx, Depth: Integer);
var
  I, J: Integer;
  Name, Arg, Rest, FName, Item: string;
  Truth, Cur: Boolean;
  Letter: Char;
  Top: Integer;
  IncText: string;
  Parts: TStringList;
  P: string;

  procedure Err(const Msg: string);
  begin
    raise EMKCompile.CreateAt(Msg, L, C, Files[FileIdx]);
  end;

begin
  { name = leading letters }
  I := 1;
  while (I <= Length(Text)) and (Text[I] in ['A'..'Z', 'a'..'z']) do Inc(I);
  Name := UpperCase(Copy(Text, 1, I - 1));
  Rest := Trim(Copy(Text, I, MaxInt));
  Arg := Rest;
  J := 1;
  while (J <= Length(Arg)) and not (Arg[J] in [' ', #9, #13, #10]) do Inc(J);
  Arg := Copy(Arg, 1, J - 1);

  if (Name = 'IFDEF') or (Name = 'IFNDEF') or (Name = 'IFOPT') then
  begin
    if Name = 'IFOPT' then
    begin
      Letter := #0;
      if Arg <> '' then Letter := UpCase(Arg[1]);
      Cur := (SwBit(Letter) and FSw) <> 0;
      Truth := Cur = ((Length(Arg) >= 2) and (Arg[2] = '+'));
    end
    else
    begin
      Truth := FDefines.IndexOf(Arg) >= 0;
      if Name = 'IFNDEF' then Truth := not Truth;
    end;
    if FCondCount >= Length(FCond) then SetLength(FCond, FCondCount + 8);
    FCond[FCondCount].ParentActive := not Skipping;
    FCond[FCondCount].Active := FCond[FCondCount].ParentActive and Truth;
    FCond[FCondCount].Taken := FCond[FCondCount].Active;
    FCond[FCondCount].Line := L;
    FCond[FCondCount].FileIdx := FileIdx;
    Inc(FCondCount);
    Exit;
  end;
  if Name = 'ELSE' then
  begin
    if FCondCount = 0 then Err('{$ELSE} without {$IFDEF}');
    Top := FCondCount - 1;
    FCond[Top].Active := FCond[Top].ParentActive and not FCond[Top].Taken;
    FCond[Top].Taken := FCond[Top].Taken or FCond[Top].Active;
    Exit;
  end;
  if Name = 'ENDIF' then
  begin
    if FCondCount = 0 then Err('{$ENDIF} without {$IFDEF}');
    Dec(FCondCount);
    Exit;
  end;
  if Skipping then Exit;
  if Name = 'DEFINE' then begin FDefines.Add(Arg); Exit; end;
  if Name = 'UNDEF' then
  begin
    J := FDefines.IndexOf(Arg);
    if J >= 0 then FDefines.Delete(J);
    Exit;
  end;
  if ((Name = 'I') or (Name = 'INCLUDE')) and (Rest <> '') and (Length(Text) > Length(Name)) and
     (Text[Length(Name) + 1] in [' ', #9]) then
  begin
    FName := Rest;
    if (Length(FName) >= 2) and (FName[1] = '''') and (FName[Length(FName)] = '''') then
      FName := Copy(FName, 2, Length(FName) - 2);
    if Depth >= 16 then Err('Include files nested too deeply: ' + FName);
    if not Assigned(FInclude) then Err('Include files are not available: ' + FName);
    if not FInclude(FName, IncText) then Err('Include file not found: ' + FName);
    Files.Add(FName);
    Scan(IncText, Files.Count - 1, Depth + 1);
    Exit;
  end;
  // compiler switches: R+ or I-,R+ style
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ',';
    Parts.StrictDelimiter := True;
    P := Text;
    J := Pos(' ', P);
    if J > 0 then P := Copy(P, 1, J - 1);
    Parts.DelimitedText := P;
    for J := 0 to Parts.Count - 1 do
    begin
      Item := Parts[J];
      if (Length(Item) = 2) and (UpCase(Item[1]) in ['A'..'Z']) and (Item[2] in ['+', '-']) then
      begin
        if Item[2] = '+' then FSw := FSw or SwBit(Item[1]) else FSw := FSw and not SwBit(Item[1]);
      end;
    end;
  finally
    Parts.Free;
  end;
end;

procedure TLexer.Scan(const Src: string; FileIdx, Depth: Integer);
var
  I, N, Line, LineStart: Integer;
  C: Char;
  Tok: TToken;
  J, Start, StartLine, StartCol, BodyStart: Integer;
  Close: string;
  Body, Str, Two: string;
  Code: Integer;
  IsReal: Boolean;
  Sym: Boolean;

  procedure Err(const Msg: string; L, Cc: Integer);
  begin
    raise EMKCompile.CreateAt(Msg, L, Cc, Files[FileIdx]);
  end;

begin
  I := 1;
  N := Length(Src);
  Line := 1;
  LineStart := 1;
  while I <= N do
  begin
    C := Src[I];
    if C = #10 then begin Inc(I); Inc(Line); LineStart := I; Continue; end;
    if C in [' ', #9, #13, #12, #26] then begin Inc(I); Continue; end;
    if (C = '{') or ((C = '(') and (I < N) and (Src[I + 1] = '*')) then   // comment or directive
    begin
      StartLine := Line;
      StartCol := I - LineStart + 1;
      if C = '{' then begin Close := '}'; J := I + 1; end else begin Close := '*)'; J := I + 2; end;
      BodyStart := J;
      while (J <= N) and (Copy(Src, J, Length(Close)) <> Close) do
      begin
        if Src[J] = #10 then begin Inc(Line); LineStart := J + 1; end;
        Inc(J);
      end;
      if J > N then Err('Unterminated comment', StartLine, StartCol);
      Body := Copy(Src, BodyStart, J - BodyStart);
      I := J + Length(Close);
      if (Body <> '') and (Body[1] = '$') then
        Directive(Copy(Body, 2, MaxInt), StartLine, StartCol, FileIdx, Depth);
      Continue;
    end;
    if (C = '/') and (I < N) and (Src[I + 1] = '/') then
    begin
      while (I <= N) and (Src[I] <> #10) do Inc(I);
      Continue;
    end;

    FillChar(Tok, SizeOf(Tok), 0);
    Tok.Line := Line;
    Tok.Col := I - LineStart + 1;
    Tok.FileIdx := FileIdx;
    Tok.Sw := FSw;

    if IsAlpha(C) then
    begin
      Start := I;
      while (I <= N) and (IsAlpha(Src[I]) or IsDigit(Src[I])) do Inc(I);
      Tok.Text := Copy(Src, Start, I - Start);
      Tok.Key := LowerCase(Tok.Text);
      if IsKeyword(Tok.Key) then Tok.Kind := tkKeyword else Tok.Kind := tkIdent;
    end
    else if IsDigit(C) or ((C = '$') and (I < N) and IsHex(Src[I + 1])) then
    begin
      if C = '$' then
      begin
        Inc(I);
        Start := I;
        while (I <= N) and IsHex(Src[I]) do Inc(I);
        Tok.Kind := tkInt;
        Tok.IntVal := StrToInt64('$' + Copy(Src, Start, I - Start));
      end
      else
      begin
        Start := I;
        while (I <= N) and IsDigit(Src[I]) do Inc(I);
        IsReal := False;
        if (I < N) and (Src[I] = '.') and IsDigit(Src[I + 1]) then
        begin
          IsReal := True;
          Inc(I);
          while (I <= N) and IsDigit(Src[I]) do Inc(I);
        end;
        if (I <= N) and (Src[I] in ['e', 'E']) and (I < N) and
           (IsDigit(Src[I + 1]) or ((Src[I + 1] in ['+', '-']) and (I + 1 < N) and IsDigit(Src[I + 2]))) then
        begin
          IsReal := True;
          Inc(I, 2);
          while (I <= N) and IsDigit(Src[I]) do Inc(I);
        end;
        if IsReal then
        begin
          Tok.Kind := tkReal;
          Tok.RealVal := StrToFloat(StringReplace(Copy(Src, Start, I - Start), '.', DefaultFormatSettings.DecimalSeparator, []));
        end
        else
        begin
          Tok.Kind := tkInt;
          if not TryStrToInt64(Copy(Src, Start, I - Start), Tok.IntVal) then
            Err('Integer constant too large', Tok.Line, Tok.Col);
        end;
      end;
    end
    else if (C = '''') or (C = '#') then
    begin
      Str := '';
      while (I <= N) and ((Src[I] = '''') or (Src[I] = '#')) do
      begin
        if Src[I] = '''' then
        begin
          Inc(I);
          while True do
          begin
            if (I > N) or (Src[I] = #10) then
            begin
              if Skipping then Break;
              Err('String exceeds line', Tok.Line, Tok.Col);
            end;
            if Src[I] = '''' then
            begin
              if (I < N) and (Src[I + 1] = '''') then begin Str := Str + ''''; Inc(I, 2); Continue; end;
              Inc(I);
              Break;
            end;
            Str := Str + Src[I];
            Inc(I);
          end;
        end
        else
        begin
          Inc(I);
          Start := I;
          if (I <= N) and (Src[I] = '$') then
          begin
            Inc(I);
            Start := I;
            while (I <= N) and IsHex(Src[I]) do Inc(I);
            Code := StrToIntDef('$' + Copy(Src, Start, I - Start), -1);
          end
          else
          begin
            while (I <= N) and IsDigit(Src[I]) do Inc(I);
            Code := StrToIntDef(Copy(Src, Start, I - Start), -1);
          end;
          if (Code < 0) or (Code > 255) then
          begin
            if not Skipping then Err('Illegal character constant', Tok.Line, Tok.Col);
            Code := 0;
          end;
          Str := Str + Chr(Code);
        end;
      end;
      Tok.Kind := tkString;
      Tok.Text := Str;
    end
    else
    begin
      Two := Copy(Src, I, 2);
      Sym := True;
      if (Two = ':=') or (Two = '<=') or (Two = '>=') or (Two = '<>') or (Two = '..') then
      begin
        Tok.Key := Two;
        Inc(I, 2);
      end
      else if C in ['+', '-', '*', '/', '=', '<', '>', '(', ')', '[', ']', ',', ';', ':', '.', '^', '@'] then
      begin
        Tok.Key := C;
        Inc(I);
      end
      else
      begin
        Sym := False;
        if Skipping then begin Inc(I); Continue; end;
        Err('Illegal character ''' + C + '''', Tok.Line, Tok.Col);
      end;
      if Sym then begin Tok.Kind := tkSym; Tok.Text := Tok.Key; end;
    end;
    if not Skipping then Push(Tok);
  end;
end;

procedure TLexer.Tokenize(const Src: string);
var
  Eof: TToken;
  Last: Integer;
begin
  Count := 0;
  FCondCount := 0;
  Scan(Src, 0, 0);
  if FCondCount > 0 then
  begin
    Last := FCondCount - 1;
    raise EMKCompile.CreateAt('Missing {$ENDIF} for the {$IF...} at line ' + IntToStr(FCond[Last].Line),
      FCond[Last].Line, 1, Files[FCond[Last].FileIdx]);
  end;
  FillChar(Eof, SizeOf(Eof), 0);
  Eof.Kind := tkEOF;
  Eof.Text := '<end of file>';
  if Count > 0 then begin Eof.Line := Toks[Count - 1].Line; Eof.Col := Toks[Count - 1].Col; end else Eof.Line := 1;
  Eof.Sw := FSw;
  Push(Eof);
  Dec(Count);          // keep the EOF token just past Count so Toks[Count] is always valid
end;

initialization
  KeywordSet := TStringList.Create;
  KeywordSet.Sorted := True;
  KeywordSet.CaseSensitive := True;
  KeywordSet.CommaText := 'and,array,asm,begin,case,const,constructor,destructor,div,do,downto,else,end,file,for,' +
    'function,goto,if,implementation,in,inherited,inline,interface,label,mod,nil,not,object,of,or,packed,' +
    'procedure,program,record,repeat,set,shl,shr,string,then,to,type,unit,until,uses,var,while,with,xor';
finalization
  KeywordSet.Free;
end.
