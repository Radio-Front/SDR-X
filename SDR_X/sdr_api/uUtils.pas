unit uUtils;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IniFiles;

var
  // Глобальний об'єкт INI-файлу, доступний усім модулям через "uUtils.AppIni"
  AppIni: TIniFile = nil;

function GetBitness: Integer;
function GetIniPath: string;
procedure InitAppConfig;
procedure CloseAppConfig;

implementation

uses uLogger;

function GetBitness: Integer;
begin
  {$IFDEF WIN64}
  Result := 64;
  {$ELSE}
  Result := 32;
  {$ENDIF}
end;

function GetIniPath: string;
begin
  Result := ChangeFileExt(ParamStr(0), '.ini');
end;

// НАЙПЕРШИЙ ТАКТ: Ініціалізація файлу конфігурації
procedure InitAppConfig;
begin
  var Path := GetIniPath;

  if not FileExists(Path) then
  begin
    LL('⚙️ Конфігурація: Файл налаштувань не знайдено (перший запуск або портативний перенос).');
    LL('⚙️ Конфігурація: Програма SDR-X починає роботу з налаштуваннями за замовчуванням.');
  end;

  // Створюємо глобальний об'єкт (файл на диску створиться фізично лише при першому записі)
  AppIni := TIniFile.Create(Path);
end;

// ФІНАЛЬНИЙ ТАКТ: Безпечне закриття файлу
procedure CloseAppConfig;
begin
  if Assigned(AppIni) then
    FreeAndNil(AppIni);
end;

initialization
  AppIni := nil;

finalization
  CloseAppConfig;

end.

