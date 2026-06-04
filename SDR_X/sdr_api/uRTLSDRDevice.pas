unit uRTLSDRDevice;

interface

uses
  System.Classes, System.SysUtils, uSDRDevice, rtlsdr;

type
  // Фоновий асинхронний потік читання, стійкий до гарячого відключення
  TRTLThread = class(TThread)
  private
    FDevHandle: Prtlsdr_dev_t;
    FCallback: TOnIQData;
    procedure NativeCallback(buf: Pointer; len: Cardinal);
  protected
    procedure Execute; override;
  public
    constructor Create(AHandle: Prtlsdr_dev_t; ACallback: TOnIQData);
  end;

  // Конкретний клас приймача для RTL-SDR чіпів
  TRTLSDRDevice = class(TSDRDevice)
  private
    FHandle: Prtlsdr_dev_t;
    FThread: TRTLThread;
    procedure HandleInternalIQData(const Buffer: TIQBuffer);
  public
    destructor Destroy; override;
    function Connect: Boolean; override;
    procedure Disconnect; override;
    function SetCenterFreq(const AFreqHz: Cardinal): Boolean; override;
    function SetSampleRate(const ARateHz: Cardinal): Boolean; override;
  end;

function ScanRTLSDR: TStringList;

implementation

uses uLogger;

// Зворотний С-виклик для нативної бібліотеки rtlsdr.dll
procedure RtlSdrCdeclCallback(buf: Pointer; len: Cardinal; ctx: Pointer); cdecl;
begin
  if Assigned(ctx) then
    TRTLThread(ctx).NativeCallback(buf, len);
end;

{ TRTLThread }

constructor TRTLThread.Create(AHandle: Prtlsdr_dev_t; ACallback: TOnIQData);
begin
  inherited Create(True);
  FDevHandle := AHandle;
  FCallback := ACallback;
  FreeOnTerminate := False; // Керування пам'яттю залишається суворо за Delphi
end;

procedure TRTLThread.NativeCallback(buf: Pointer; len: Cardinal);
begin
  if Terminated or (len = 0) or (buf = nil) or not Assigned(FCallback) then Exit;

  try
    var TempBuf: TIQBuffer;
    SetLength(TempBuf, len);
    Move(buf^, TempBuf, len);
    FCallback(TempBuf);
  except
    on E: Exception do
    begin
      // 🛡️ Використовуємо нову процедуру EL для фіксації помилок потоку
      EL('КРИТИЧНА ПОМИЛКА DSP ПОТОКУ у NativeCallback: ' + E.Message);
      Self.Terminate;
    end;
  end;
end;

procedure TRTLThread.Execute;
begin
  LL('SDR потік: запуск асинхронного циклу...');
  rtlsdr_reset_buffer(FDevHandle);
  var Res := rtlsdr_read_async(FDevHandle, RtlSdrCdeclCallback, Self, 15, 131072);
  if Res < 0 then
    LL('SDR потік: асинхронне читання зупинено або залізо відключено.');
end;

{ TRTLSDRDevice }

destructor TRTLSDRDevice.Destroy;
begin
  Disconnect;
  inherited;
end;

function TRTLSDRDevice.Connect: Boolean;
begin
  Result := False;
  if FIsConnected then Exit(True);

  if not IsSDRLibraryLoaded then
    if not LoadRTLSRD('rtlsdr.dll') then Exit;

  var OpenDone := False;
  var Res: Integer := -1;

  // Захист таймаутом на випадок зависання USB-порту
  var OpenThread := TThread.CreateAnonymousThread(procedure
    begin
      try
        Res := rtlsdr_open(FHandle, FDeviceIndex);
        OpenDone := True;
      except
        OpenDone := True;
      end;
    end);
  OpenThread.Start;

  var WaitCounter := 0;
  while (not OpenDone) and (WaitCounter < 150) do
  begin
    Sleep(10);
    Inc(WaitCounter);
  end;

  if not OpenDone then
  begin
    // 🛡️ Реєструємо апаратний збій через EL
    EL('КРИТИЧНА ПОМИЛКА: Драйвер заклинило на стадії rtlsdr_open! Операцію скасовано.');
    Exit(False);
  end;

  if Res < 0 then Exit(False);

  // Безпечне налаштування регістрів чипа
  try
    FIsConnected := True;
    SetSampleRate(FSampleRate);
    rtlsdr_set_tuner_gain_mode(FHandle, 0);
    SetCenterFreq(FCenterFreq);

    FThread := TRTLThread.Create(FHandle, HandleInternalIQData);
    FThread.Start;
    Result := True;
  except
    on E: Exception do
    begin
      // 🛡️ Записуємо збій регістрів через EL
      EL('КРИТИЧНА ПОМИЛКА під час налаштування регістрів чипа RTL-SDR: ' + E.Message);
      if Assigned(FHandle) then
      begin
        try rtlsdr_close(FHandle); except end;
        FHandle := nil;
      end;
      FIsConnected := False;
      Result := False;
    end;
  end;
end;

procedure TRTLSDRDevice.Disconnect;
begin
  if FIsConnected and Assigned(FHandle) then
  begin
    try rtlsdr_cancel_async(FHandle); except end;
  end;

  if Assigned(FThread) then
  begin
    try
      if not FThread.Finished then
      begin
        FThread.Terminate;
        FThread.WaitFor;
      end;
    except
    end;

    try
      var FreeingThread := FThread;
      FThread := nil;
      FreeingThread.Free; // Чисте руйнування без попереджень компилятора
    except
    end;
  end;

  if FIsConnected and Assigned(FHandle) then
  begin
    try rtlsdr_close(FHandle); except end;
    FHandle := nil;
  end;
  FIsConnected := False;
end;

function TRTLSDRDevice.SetCenterFreq(const AFreqHz: Cardinal): Boolean;
begin
  Result := False;
  FCenterFreq := AFreqHz;
  if FIsConnected and Assigned(FHandle) then
    Result := (rtlsdr_set_center_freq(FHandle, FCenterFreq) = 0);
end;

function TRTLSDRDevice.SetSampleRate(const ARateHz: Cardinal): Boolean;
begin
  Result := False;
  FSampleRate := ARateHz;
  if FIsConnected and Assigned(FHandle) then
    Result := (rtlsdr_set_sample_rate(FHandle, FSampleRate) = 0);
end;

procedure TRTLSDRDevice.HandleInternalIQData(const Buffer: TIQBuffer);
begin
  if Assigned(FOnIQDataReceived) then FOnIQDataReceived(Buffer);
end;

function ScanRTLSDR: TStringList;
begin
  Result := TStringList.Create;
  if not IsSDRLibraryLoaded then LoadRTLSRD('rtlsdr.dll');
  if not IsSDRLibraryLoaded then Exit;

  var DeviceCount: Integer := 0;
  var HardwareDone := False;

  var ProbeThread := TThread.CreateAnonymousThread(procedure
    begin
      try
        DeviceCount := rtlsdr_get_device_count;
        HardwareDone := True;
      except
        HardwareDone := True;
      end;
    end);
  ProbeThread.Start;

  var WaitCounter := 0;
  while (not HardwareDone) and (WaitCounter < 150) do
  begin
    Sleep(10);
    Inc(WaitCounter);
  end;

  if not HardwareDone then
  begin
    // 🛡️ Позначаємо аварію опитування шини через EL
    EL('УВАГА: USB-шина заблокована драйвером Windows. Сканування пристроїв перервано.');
    Exit;
  end;

  try
    for var i := 0 to DeviceCount - 1 do
      Result.Add(Format('%d: RTL-SDR v3 (%s)', [i, AnsiString(rtlsdr_get_device_name(i))]));
  except
  end;
end;

end.

