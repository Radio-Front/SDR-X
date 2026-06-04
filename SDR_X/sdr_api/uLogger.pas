unit uLogger;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs;

type
  TLogNotifyEvent = procedure(const LogLine: string) of object;

// Глобальні процедури, доступні з будь-якого модуля
procedure LL(const S: string);
procedure EL(const S: string); // 👈 ДОДАНО: Спеціальна процедура для логування помилок
procedure InitLogger(OnLogEvent: TLogNotifyEvent = nil);

implementation

var
  FLogPath: string;
  FOnLog: TLogNotifyEvent;
  FLogLock: TCriticalSection;

function GetDefaultLogPath: string;
begin
  Result := ChangeFileExt(ParamStr(0), '.ini'); // Заміна розширення на .log робиться нижче
  Result := ChangeFileExt(Result, '.log');
end;

procedure InitLogger(OnLogEvent: TLogNotifyEvent);
begin
  FOnLog := OnLogEvent;
  FLogPath := GetDefaultLogPath;

  try
    var ClearStream := TFileStream.Create(FLogPath, fmCreate);
    ClearStream.Free;
  except
  end;
end;

// Внутрішній універсальний метод запису (щоб не дублювати код)
procedure WriteToLogSystem(const MessageText: string; const IsError: Boolean);
begin
  var TimeStamp := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);

  // Якщо це помилка — вставляємо маркер [!], якщо звичайний лог — просто пробіл
  var LogLine: string;
  if IsError then
    LogLine := Format('%s [!] %s', [TimeStamp, MessageText])
  else
    LogLine := Format('%s %s', [TimeStamp, MessageText]);

  FLogLock.Enter;
  try
    // 1. Запис у текстовий файл логу
    if FLogPath <> '' then
    begin
      try
        var LogStream := TFileStream.Create(FLogPath, fmOpenWrite or fmShareDenyNone);
        try
          LogStream.Seek(0, TSeekOrigin.soEnd);
          var Bytes := TEncoding.UTF8.GetBytes(LogLine + sLineBreak);
          LogStream.WriteBuffer(Bytes, Length(Bytes));
        finally
          LogStream.Free;
        end;
      except
      end;
    end;

    // 2. Передача рядка на форму через Callback
    if Assigned(FOnLog) then
    begin
      TThread.Queue(nil, procedure
        begin
          if Assigned(FOnLog) then
            FOnLog(LogLine);
        end);
    end;

  finally
    FLogLock.Leave;
  end;
end;

procedure LL(const S: string);
begin
  WriteToLogSystem(S, False); // Звичайний запис
end;

procedure EL(const S: string);
begin
  WriteToLogSystem(S, True);  // 🚀 Запис помилки з маркером [!]
end;

initialization
  FLogLock := TCriticalSection.Create;
  FLogPath := '';
  FOnLog := nil;

finalization
  FLogLock.Free;

end.

