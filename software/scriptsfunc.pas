unit scriptsfunc;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Variants, Dialogs, graphics,
  usbasp25, msgstr, PasCalc;

procedure SetScriptFunctions(PC : TPasCalc);
procedure SetScriptVars();
procedure RunScript(ScriptText: TStrings);
function RunScriptFromFile(ScriptFile: string; Section: string): boolean;
function ParseScriptText(Script: TStrings; SectionName: string; var ScriptText: TStrings ): Boolean;

implementation

uses main, scriptedit;


{Возвращает текст выбранной секции
 Если секция не найдена возвращает false}
function ParseScriptText(Script: TStrings; SectionName: string; var ScriptText: TStrings ): Boolean;
var
  st: string;
  i: integer;
  s: boolean;
begin
  Result := false;
  s:= false;

  for i:=0 to Script.Count-1 do
  begin
    st:= Script.Strings[i];

    if s then
    begin
      if Trim(Copy(st, 1, 2)) = '{$' then break;
      ScriptText.Append(st);
    end
    else
    begin
      st:= StringReplace(st, ' ', '', [rfReplaceAll]);
      if Pos('{$' + Upcase(SectionName) + '}', Upcase(st)) <> 0 then
      //if Upcase(st) = '{$' + Upcase(SectionName) + '}' then
      begin
        s := true;
        Result := true;
      end;
    end;

  end;
end;

//Выполняет скрипт
procedure RunScript(ScriptText: TStrings);
var
  TimeCounter: TDateTime;
begin
  LogPrint(TimeToStr(Time()));
  TimeCounter := Time();
  MainForm.Log.Append(STR_USING_SCRIPT + CurrentICParam.Script);

  RomF.Clear;

  //Предопределяем переменные
  ScriptEngine.ClearVars;
  SyncUI_ICParam();
  SetScriptVars();

  MainForm.StatusBar.Panels.Items[2].Text := CurrentICParam.Name;
  ScriptEngine.Execute(ScriptText.Text);

  if ScriptEngine.ErrCode<>0 then
  begin
    if not ScriptEditForm.Visible then
    begin
      LogPrint(ScriptEngine.ErrMsg, clRed);
      LogPrint(ScriptEngine.ErrLine, clRed);
    end
    else
    begin
      ScriptLogPrint(ScriptEngine.ErrMsg, clRed);
      ScriptLogPrint(ScriptEngine.ErrLine, clRed);
    end;
  end;

  LogPrint(STR_TIME + TimeToStr(Time() - TimeCounter));
end;

{Выполняет секцию скрипта из файла
 Если файл или секция отсутствует то возвращает false}
function RunScriptFromFile(ScriptFile: string; Section: string): boolean;
var
  ScriptText, ParsedScriptText: TStrings;
begin
  if not FileExists(ScriptsPath+ScriptFile) then Exit(false);
  try
    ScriptText:= TStringList.Create;
    ParsedScriptText:= TStringList.Create;

    ScriptText.LoadFromFile(ScriptsPath+ScriptFile);
    if not ParseScriptText(ScriptText, Section, ParsedScriptText) then Exit(false);
    RunScript(ParsedScriptText);
    Result := true;
  finally
    ScriptText.Free;
    ParsedScriptText.Free;
  end;
end;

function VarIsString(V : TVar) : boolean;
var t: integer;
begin
  t := VarType(V.Value);
  Result := (t=varString) or (t=varOleStr);
end;

//------------------------------------------------------------------------------

{Script ShowMessage(text);
 Аналог ShowMessage}
function Script_ShowMessage(Sender:TObject; var A:TVarList) : boolean;
var s: string;
begin
  if A.Count < 1 then Exit(false);

  s := TPVar(A.Items[0])^.Value;
  ShowMessage(s);
  Result := true;
end;

{Script LogPrint(text, color);
 Выводит сообщение в лог
 Параметры:
   text текст сообщения
   необязательный параметр color цвет bgr}
function Script_LogPrint(Sender:TObject; var A:TVarList) : boolean;
var
  s: string;
  color: TColor;
begin
  if A.Count < 1 then Exit(false);

  color := 0;
  if A.Count > 1 then color := TPVar(A.Items[1])^.Value;

  s := TPVar(A.Items[0])^.Value;
  LogPrint('Script: ' + s, color);
  Result := true;
end;

{Script CreateByteArray(size): variant;
 Создает массив с типом элементов varbyte}
function Script_CreateByteArray(Sender:TObject; var A:TVarList; var R:TVar) : boolean;
begin
  if A.Count < 1 then Exit(false);
  R.Value := VarArrayCreate([0, TPVar(A.Items[0])^.Value - 1], varByte);
  Result := true;
end;

{Script GetArrayItem(array, index): variant;
 Возвращает значение элемента массива}
function Script_GetArrayItem(Sender:TObject; var A:TVarList; var R:TVar) : boolean;
begin
  if (A.Count < 2) or (not VarIsArray(TPVar(A.Items[0])^.Value)) then Exit(false);
  R.Value := TPVar(A.Items[0])^.Value[TPVar(A.Items[1])^.Value];
  Result := true;
end;

{Script SetArrayItem(array, index, value);
 Устанавливает значение элемента массива}
function Script_SetArrayItem(Sender:TObject; var A:TVarList) : boolean;
begin
  if (A.Count < 3) or (not VarIsArray(TPVar(A.Items[0])^.Value)) then Exit(false);
  TPVar(A.Items[0])^.Value[TPVar(A.Items[1])^.Value] := TPVar(A.Items[2])^.Value;
  Result := true;
end;

{Script IntToHex(value, digits): string;
 Аналог IntToHex}
function Script_IntToHex(Sender:TObject; var A:TVarList; var R:TVar) : boolean;
begin
  if A.Count < 2 then Exit(false);

  R.Value:= IntToHex(Int64(TPVar(A.Items[0])^.Value), TPVar(A.Items[1])^.Value);
  Result := true;
end;

{Script SPISetSpeed(speed): boolean;
 Устанавливает частоту SPI
 Если частота не установлена возвращает false
 Игнорируется для CH341}
function Script_SPISetSpeed(Sender:TObject; var A:TVarList; var R:TVar) : boolean;
var speed: byte;
begin
  if A.Count < 1 then Exit(false);

  speed := TPVar(A.Items[0])^.Value;
  if UsbAsp_SetISPSpeed(hUSBDev, speed) <> 0 then
    R.Value := False
  else
    R.Value := True;
  Result := true;
end;

{Script SPIEnterProgMode();
 Инициализирует состояние пинов для SPI и устанавливает скорость}
function Script_SPIEnterProgMode(Sender:TObject; var A:TVarList) : boolean;
begin
  EnterProgMode25(hUSBdev);
  Result := true;
end;

{Script SPIExitProgMode();
 Отключает пины SPI}
function Script_SPIExitProgMode(Sender:TObject; var A:TVarList) : boolean;
begin
  ExitProgMode25(hUSBdev);
  Result := true;
end;

{Script ProgressBar(inc, max, pos);
 Устанавливает состояние ProgressBar
 Параметры:
   inc насколько увиличить позицию
 Необязательные параметры:
   max максимальная позиция ProgressBar
   pos устанавливает конкретную позицию ProgressBar}
function Script_ProgressBar(Sender:TObject; var A:TVarList) : boolean;
begin

  if A.Count < 1 then Exit(false);

  MainForm.ProgressBar.Position := MainForm.ProgressBar.Position + TPVar(A.Items[0])^.Value;

  if A.Count > 1 then
    MainForm.ProgressBar.Max := TPVar(A.Items[1])^.Value;
  if A.Count > 2 then
    MainForm.ProgressBar.Position := TPVar(A.Items[2])^.Value;

  Result := true;
end;

{Script SPIRead(cs, size, buffer..): integer;
 Читает данные в буфер
 Параметры:
   cs если cs=1 отпускать Chip Select после чтения данных
   size размер данных в байтах
   buffer переменные для хранения данных или массив созданный CreateByteArray
 Возвращает количество прочитанных байт}
function Script_SPIRead(Sender:TObject; var A:TVarList; var R: TVar) : boolean;
var
  i, size, cs: integer;
  DataArr: array of byte;
begin

  if A.Count < 3 then Exit(false);

  cs := TPVar(A.Items[0])^.Value;
  size := TPVar(A.Items[1])^.Value;

  SetLength(DataArr, size);

  R.Value := SPIRead(hUSBdev, cs, size, DataArr[0]);

  //Если buffer массив
  if (VarIsArray(TPVar(A.Items[2])^.Value)) then
  for i := 0 to size-1 do
  begin
    TPVar(A.Items[2])^.Value[i] := DataArr[i];
  end
  else
  for i := 0 to size-1 do
  begin
    TPVar(A.Items[i+2])^.Value := DataArr[i];
  end;

  Result := true;
end;

{Script SPIWrite(cs, size, buffer..): integer;
 Записывает данные из буфера
 Параметры:
   cs если cs=1 отпускать Chip Select после записи данных
   size размер данных в байтах
   buffer переменные для хранения данных или массив созданный CreateByteArray
 Возвращает количество записанных байт}
function Script_SPIWrite(Sender:TObject; var A:TVarList; var R: TVar) : boolean;
var
  i, size, cs: integer;
  DataArr: array of byte;
begin

  if A.Count < 3 then Exit(false);

  size := TPVar(A.Items[1])^.Value;
  cs := TPVar(A.Items[0])^.Value;
  SetLength(DataArr, size);

  //Если buffer массив
  if (VarIsArray(TPVar(A.Items[2])^.Value)) then
  for i := 0 to size-1 do
  begin
    DataArr[i] := TPVar(A.Items[2])^.Value[i];
  end
  else
  for i := 0 to size-1 do
  begin
    DataArr[i] := TPVar(A.Items[i+2])^.Value;
  end;

  R.Value := SPIWrite(hUSBdev, cs, size, DataArr);
  Result := true;
end;

{Script SPIReadToEditor(cs, size): integer;
 Читает данные в редактор
 Параметры:
   cs если cs=1 отпускать Chip Select после чтения данных
   size размер данных в байтах
 Возвращает количество прочитанных байт}
function Script_SPIReadToEditor(Sender:TObject; var A:TVarList; var R: TVar) : boolean;
var
  DataArr: array of byte;
  BufferLen: integer;
begin

  if A.Count < 2 then Exit(false);

  BufferLen := TPVar(A.Items[1])^.Value;
  SetLength(DataArr, BufferLen);

  R.Value := SPIRead(hUSBdev, TPVar(A.Items[0])^.Value, BufferLen, DataArr[0]);

  RomF.WriteBuffer(DataArr[0], BufferLen);
  RomF.Position := 0;
  MainForm.KHexEditor.LoadFromStream(RomF);
  Result := true;
end;

{Script SPIWriteFromEditor(cs, size, position): integer;
 Записывает данные из редактора размером size с позиции position
 Параметры:
   cs если cs=1 отпускать Chip Select после записи данных
   size размер данных в байтах
   position позиция в редакторе
 Возвращает количество записанных байт}
function Script_SPIWriteFromEditor(Sender:TObject; var A:TVarList; var R: TVar) : boolean;
var
  DataArr: array of byte;
  BufferLen: integer;
begin

  if A.Count < 3 then Exit(false);

  BufferLen := TPVar(A.Items[1])^.Value;
  SetLength(DataArr, BufferLen);

  RomF.Clear;
  MainForm.KHexEditor.SaveToStream(RomF);
  RomF.Position := TPVar(A.Items[2])^.Value;
  RomF.ReadBuffer(DataArr[0], BufferLen);

  R.Value := SPIWrite(hUSBdev, TPVar(A.Items[0])^.Value, BufferLen, DataArr);

  Result := true;
end;

//------------------------------------------------------------------------------
procedure SetScriptFunctions(PC : TPasCalc);
begin
  PC.SetFunction('ShowMessage', @Script_ShowMessage);
  PC.SetFunction('LogPrint', @Script_LogPrint);
  PC.SetFunction('ProgressBar', @Script_ProgressBar);
  PC.SetFunction('IntToHex', @Script_IntToHex);

  PC.SetFunction('CreateByteArray', @Script_CreateByteArray);
  PC.SetFunction('GetArrayItem', @Script_GetArrayItem);
  PC.SetFunction('SetArrayItem', @Script_SetArrayItem);

  PC.SetFunction('SPISetSpeed', @Script_SPISetSpeed);
  PC.SetFunction('SPIEnterProgMode', @Script_SPIEnterProgMode);
  PC.SetFunction('SPIExitProgMode', @Script_SPIExitProgMode);
  PC.SetFunction('SPIRead', @Script_SPIRead);
  PC.SetFunction('SPIWrite', @Script_SPIWrite);
  PC.SetFunction('SPIReadToEditor', @Script_SPIReadToEditor);
  PC.SetFunction('SPIWriteFromEditor', @Script_SPIWriteFromEditor);

end;

procedure SetScriptVars();
begin
  ScriptEngine.SetValue('_IC_Name', CurrentICParam.Name);
  ScriptEngine.SetValue('_IC_Size', CurrentICParam.Size);
  ScriptEngine.SetValue('_IC_Page', CurrentICParam.Page);
  ScriptEngine.SetValue('_IC_SpiCmd', CurrentICParam.SpiCmd);
  ScriptEngine.SetValue('_IC_MWAddrLen', CurrentICParam.MWAddLen);
  ScriptEngine.SetValue('_IC_I2CAddrType', CurrentICParam.I2CAddrType);
end;

end.

