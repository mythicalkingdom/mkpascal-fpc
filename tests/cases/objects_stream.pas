program ObjStream;
uses Objects;
type
  TRec = record
    A: Integer;
    B: Longint;
    S: string[7];
  end;
var
  M: TMemoryStream;
  EF: file;
  D: PDosStream;
  R, R2: TRec;
  W: Word;
  P: PString;
  C: PChar;
  I: Integer;
  b: Byte;
begin
  M.Init;
  R.A := 7; R.B := 123456; R.S := 'abc';
  M.Write(R, SizeOf(R));
  M.WriteStr(NewStr('hello'));
  M.StrWrite('zero term');
  WriteLn(M.GetSize, ' ', M.GetPos);
  M.Seek(0);
  M.Read(R2, SizeOf(R2));
  WriteLn(R2.A, ' ', R2.B, ' ', R2.S);
  P := M.ReadStr;
  WriteLn(P^);
  DisposeStr(P);
  C := M.StrRead;
  WriteLn(C);
  StrDispose(C);
  M.Read(W, 2);
  WriteLn(M.Status = stReadError, ' ', M.ErrorInfo);
  M.Reset;
  WriteLn(M.Status);
  M.Seek(2);
  M.Truncate;
  WriteLn(M.GetSize);
  M.Done;

  D := New(PDosStream, Init('data.bin', stCreate));
  for I := 1 to 10 do begin b := I * 3; D^.Write(b, 1); end;
  D^.Done;
  D := New(PDosStream, Init('data.bin', stOpenRead));
  WriteLn(D^.GetSize);
  D^.Seek(4);
  D^.Read(b, 1);
  WriteLn(b);
  b := 1;
  D^.Write(b, 1);
  WriteLn(D^.Status = stWriteError);
  Dispose(D, Done);
  D := New(PDosStream, Init('nothere.bin', stOpenRead));
  WriteLn(D^.Status = stInitError);
  Dispose(D, Done);
  Assign(EF, 'data.bin');
  Erase(EF);
  WriteLn(LongMul(300, 200), ' ', LongDiv(100000, 7));
end.
