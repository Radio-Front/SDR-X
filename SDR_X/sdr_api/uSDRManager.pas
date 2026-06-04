unit uSDRManager;

interface

uses
  System.SysUtils, System.Classes, System.UITypes, FMX.Forms, FMX.Types, FMX.Platform,
  uSDRDevice, uRTLSDRDevice, uLogger, uStopwatch;

type
  TSDRManager = class
  private
    FSDR: TSDRDevice;
    FCurrentDeviceName: string;
    FOnIQData: TOnIQData;
    procedure SetBusy(const IsBusy: Boolean);
  public
    constructor Create(AOnIQData: TOnIQData);
    destructor Destroy; override;

    function ScanAndRestore(out TargetIndex: Integer): TStringList;
    function ConnectTo(const Index: Integer; const DeviceName: string): Boolean;
    procedure Disconnect;
    function ChangeFrequency(const FreqHz: Cardinal): Boolean;

    property ActiveSDR: TSDRDevice read FSDR;
    property CurrentDeviceName: string read FCurrentDeviceName;
  end;

implementation

constructor TSDRManager.Create(AOnIQData: TOnIQData);
begin
  inherited Create;
  FOnIQData := AOnIQData;
  FSDR := nil;
  FCurrentDeviceName := '';
end;

destructor TSDRManager.Destroy;
begin
  Disconnect;
  inherited;
end;

// Перемикач стану курсору програми (Кросплатформний FMX стиль)
procedure TSDRManager.SetBusy(const IsBusy: Boolean);
begin
 // Асинхронно синхронізуємо зміну інтерфейсу через чергу головного потоку
  TThread.Queue(nil, procedure
    begin
      var CursorService: IFMXCursorService;
      // Безпечно перевіряємо, чи підтримує поточна ОС сервіс курсорів
      if TPlatformServices.Current.SupportsPlatformService(IFMXCursorService, CursorService) then
      begin
        if IsBusy then
          CursorService.SetCursor(crHourGlass) // Вмикаємо часики
        else
          CursorService.SetCursor(crDefault);  // Повертаємо стрілку
      end;
    end);
end;

// Логіка Кнопки 1: Оновлює список та шукає попередній пристрій
function TSDRManager.ScanAndRestore(out TargetIndex: Integer): TStringList;
begin
  SetBusy(True);
  try
    Result := ScanRTLSDR;
    TargetIndex := 0; // Дефолт

    if (FCurrentDeviceName <> '') and (Result.Count > 0) then
    begin
      for var i := 0 to Result.Count - 1 do
      begin
        if Pos(FCurrentDeviceName, Result[i]) > 0 then
        begin
          TargetIndex := i;
          Break;
        end;
      end;
    end;
  finally
    SetBusy(False);
  end;
end;

// Логіка підключення та вибору елемента списку
function TSDRManager.ConnectTo(const Index: Integer; const DeviceName: string): Boolean;
begin
  Result := False;

  // 🛡️ ЗАХИСТ 1: Якщо список порожній або індекс недійсний — просто виходимо
  if (Index < 0) or (DeviceName = '') then
  begin
    LL('Підключення скасовано: відсутня назва або індекс пристрою.');
    Exit;
  end;

  SetBusy(True);
  var Timer := StartTiming;
  try
    Disconnect; // Безпечно закриваємо попередній, якщо він був

    FSDR := TRTLSDRDevice.Create(Index);
    FSDR.OnIQDataReceived := FOnIQData;

    if FSDR.Connect then
    begin
      FCurrentDeviceName := DeviceName;
      LL(Format('Приймач [%s] успішно підключено за %s.', [DeviceName, GetElapsedString(Timer)]));
      Result := True;
    end
    else
    begin
      // Якщо залізо фізично не відповіло під час ініціалізації
      LL(Format('Не вдалося ініціалізувати пристрій [%s]. Перевірте USB-кабель.', [DeviceName]));
      FreeAndNil(FSDR);
    end;
  finally
    SetBusy(False);
  end;
end;


procedure TSDRManager.Disconnect;
begin
  if Assigned(FSDR) then
  begin
    SetBusy(True);
    try
      FreeAndNil(FSDR);
    finally
      SetBusy(False);
    end;
  end;
end;

function TSDRManager.ChangeFrequency(const FreqHz: Cardinal): Boolean;
begin
  Result := False;
  if Assigned(FSDR) and FSDR.IsConnected then
  begin
    Result := FSDR.SetCenterFreq(FreqHz);
  end;
end;

end.

