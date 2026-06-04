unit uUSBMonitor;

interface

uses
  System.SysUtils, System.Classes, Winapi.Windows, Winapi.Messages, FMX.Forms,
  System.Win.ComObj, Winapi.ActiveX, System.Variants, System.StrUtils,
  uLogger,
  uStopwatch; // 👈 ПІДКЛЮЧАЄМО НАШ ВИСОКОТОЧНИЙ СЕКУНДОМІР СЮДИ

type
  TUSBDeviceInfo = record
    DeviceName: string;
    VID: string;
    PID: string;
    PortNumber: Integer;
    USBVersion: string;
    DeviceID: string;
  end;

  TOnUSBDeviceEvent = procedure(const Device: TUSBDeviceInfo; const IsAdded: Boolean) of object;

  TUSBMonitor = class
  private
    FHWnd: HWND;
    FOnUSBEvent: TOnUSBDeviceEvent;
    FControllersCounted: Boolean;

    FConnectionCount: Integer;
    FDisconnectionCount: Integer;
    FLastEventTime: TPrecisionTime; // 👈 ЗАМІНЕНО тип на надточний Int64 міток тактів
    FAutoStartBlocked: Boolean;

    procedure WndProc(var Msg: TMessage);
    function ParsePNPDeviceID(const PNPDeviceID: string; out VID, PID: string): Boolean;
    procedure AsyncCountUSBControllers;
  public
    constructor Create(AEvent: TOnUSBDeviceEvent);
    destructor Destroy; override;
    function ScanUSBBus: TArray<TUSBDeviceInfo>;
    procedure ResetSessionCounters;
    property ControllersCounted: Boolean read FControllersCounted;
  end;

implementation

const
  GUID_DEVINTERFACE_USB_DEVICE: TGUID = '{A5DCBF10-6530-11D2-901F-00C04FB951ED}';
  DBT_DEVICEARRIVAL = $8000;
  DBT_DEVICEREMOVECOMPLETE = $8004;
  DBT_DEVTYP_DEVICEINTERFACE = $00000005;

type
  PDevBroadcastHeader = ^TDevBroadcastHeader;
  TDevBroadcastHeader = record
    dbch_size: DWORD;
    dbch_devicetype: DWORD;
    dbch_reserved: DWORD;
  end;

  PDevBroadcastDeviceInterface = ^TDevBroadcastDeviceInterface;
  TDevBroadcastDeviceInterface = record
    dbcc_size: DWORD;
    dbcc_devicetype: DWORD;
    dbcc_reserved: DWORD;
    dbcc_classguid: TGUID;
    dbcc_name: array[0..255] of WideChar;
  end;

// Міст для прийому системних WinAPI повідомлень Windows
function USBMonitorWndProc(hWnd: HWND; Msg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  if Msg = WM_DEVICECHANGE then
  begin
    var TMsg: TMessage;
    TMsg.Msg := Msg; TMsg.WParam := wParam; TMsg.LParam := lParam; TMsg.Result := 0;
    var Monitor := TUSBMonitor(GetWindowLongPtr(hWnd, GWLP_USERDATA));
    if Assigned(Monitor) then Monitor.WndProc(TMsg);
  end;
  Result := DefWindowProc(hWnd, Msg, wParam, lParam);
end;

{ TUSBMonitor }

constructor TUSBMonitor.Create(AEvent: TOnUSBDeviceEvent);
begin
  inherited Create;
  FOnUSBEvent := AEvent;
  FControllersCounted := False;

  FConnectionCount := 0;
  FDisconnectionCount := 0;
  FLastEventTime := 0;
  FAutoStartBlocked := False;

  FHWnd := CreateWindowEx(0, 'STATIC', 'SDRX_USB_Monitor', 0, 0, 0, 0, 0, 0, 0, HInstance, nil);
  if FHWnd <> 0 then
  begin
    SetWindowLongPtr(FHWnd, GWLP_USERDATA, LONG_PTR(Self));
    SetWindowLongPtr(FHWnd, GWLP_WNDPROC, LONG_PTR(@USBMonitorWndProc));

    var NotificationFilter: TDevBroadcastDeviceInterface;
    ZeroMemory(@NotificationFilter, SizeOf(NotificationFilter));
    NotificationFilter.dbcc_size := SizeOf(NotificationFilter);
    NotificationFilter.dbcc_devicetype := DBT_DEVTYP_DEVICEINTERFACE;
    NotificationFilter.dbcc_classguid := GUID_DEVINTERFACE_USB_DEVICE;

    RegisterDeviceNotification(FHWnd, @NotificationFilter, DEVICE_NOTIFY_WINDOW_HANDLE);
  end;

  AsyncCountUSBControllers;
end;

destructor TUSBMonitor.Destroy;
begin
  if FHWnd <> 0 then DestroyWindow(FHWnd);
  inherited;
end;

procedure TUSBMonitor.ResetSessionCounters;
begin
  FConnectionCount := 0;
  FDisconnectionCount := 0;
  FAutoStartBlocked := False;
  LL('🛡️ Монітор: Лічильники сесії USB скинуто користувачем.');
end;

procedure TUSBMonitor.AsyncCountUSBControllers;
begin
  TThread.CreateAnonymousThread(procedure
  var
    SWbemLocator, WMIService, Controllers: OleVariant;
    CtrlEnum: IEnumVariant;
    CtrlDev: OleVariant;
    Value: LongWord;
    Count: Integer;
    CtrlName: string;
  begin
    Count := 0;
    CoInitializeEx(nil, COINIT_MULTITHREADED);
    try
      try
        SWbemLocator := CreateOleObject('WbemScripting.SWbemLocator');
        WMIService := SWbemLocator.ConnectServer('.', 'root\cimv2');

        // Зчитуємо поле Name для визначення виробника чіпсета контролера
        Controllers := WMIService.ExecQuery('SELECT Name FROM Win32_USBController');
        CtrlEnum := IUnknown(Controllers._NewEnum) as IEnumVariant;

        LL('🔍 WMI Старт: Аналіз апаратної конфігурації материнської плати...');

        while CtrlEnum.Next(1, CtrlDev, Value) = S_OK do
        begin
          Inc(Count);
          CtrlName := VarToStr(CtrlDev.Name);
          LL(Format('   -> Виявлено контролер №%d: %s', [Count, CtrlName]));
        end;

        FControllersCounted := True;
        LL(Format('🔍 WMI Старт: Всього в системі знайдено %d активних USB хост-контролерів.', [Count]));
      except
        on E: Exception do
          EL('Помилка WMI інспекції чіпсета: ' + E.Message);
      end;
    finally
      CoUninitialize;
    end;
  end).Start;
end;

function TUSBMonitor.ParsePNPDeviceID(const PNPDeviceID: string; out VID, PID: string): Boolean;
begin
  Result := False; VID := ''; PID := '';
  var UpperID := UpperCase(PNPDeviceID);
  var PosVID := Pos('VID_', UpperID);
  if PosVID > 0 then VID := Copy(UpperID, PosVID + 4, 4);
  var PosPID := Pos('PID_', UpperID);
  if PosPID > 0 then PID := Copy(UpperID, PosPID + 4, 4);
  Result := (VID <> '') and (PID <> '');
end;

function TUSBMonitor.ScanUSBBus: TArray<TUSBDeviceInfo>;
var
  SWbemLocator, WMIService, Devices: OleVariant;
  Enum: IEnumVariant;
  Device: OleVariant;
  Value: LongWord;
  List: TList;
begin
  List := TList.Create;
  CoInitializeEx(nil, COINIT_MULTITHREADED);
  try
    try
      SWbemLocator := CreateOleObject('WbemScripting.SWbemLocator');
      WMIService := SWbemLocator.ConnectServer('.', 'root\cimv2');
      Devices := WMIService.ExecQuery('SELECT Caption, PNPDeviceID, DeviceID, Address, LocationInformation FROM Win32_PnPEntity WHERE PNPDeviceID LIKE "USB%"');
      Enum := IUnknown(Devices._NewEnum) as IEnumVariant;

      while Enum.Next(1, Device, Value) = S_OK do
      begin
        var CaptionStr := VarToStr(Device.Caption);
        var PnpID := VarToStr(Device.PNPDeviceID);
        var DevID := VarToStr(Device.DeviceID);

        if (Pos('RTL', UpperCase(CaptionStr)) > 0) or (Pos('SDR', UpperCase(CaptionStr)) > 0) or (Pos('BULK', UpperCase(CaptionStr)) > 0) then
        begin
          if Pos('&MI_01', UpperCase(PnpID)) > 0 then Continue;

          var Info: TUSBDeviceInfo;
          Info.DeviceName := CaptionStr; Info.DeviceID := DevID;
          ParsePNPDeviceID(PnpID, Info.VID, Info.PID);
          Info.USBVersion := 'USB 2.0 (High-Speed)';
          Info.PortNumber := 1;

          if not VarIsNull(Device.Address) then Info.PortNumber := Integer(Device.Address);
          if Info.PortNumber = 0 then
          begin
            var LocInfo := UpperCase(VarToStr(Device.LocationInformation));
            var PosPort := Pos('PORT_#', LocInfo);
            if PosPort > 0 then TryStrToInt(Copy(LocInfo, PosPort + 6, 4), Info.PortNumber);
          end;

          var ControllerQuery := WMIService.ExecQuery(Format('SELECT * FROM Win32_USBControllerDevice WHERE Dependent LIKE "%%%s%%"', [Info.VID]));
          var SubEnum := IUnknown(ControllerQuery._NewEnum) as IEnumVariant; var SubDev: OleVariant;
          if SubEnum.Next(1, SubDev, Value) = S_OK then
          begin
            var CtrlName := UpperCase(VarToStr(SubDev.Antecedent));
            if (Pos('USB 3.', CtrlName) > 0) or (Pos('XHCI', CtrlName) > 0) or (Pos('ROOT_HUB_30', CtrlName) > 0) then
              Info.USBVersion := 'USB 3.0 (SuperSpeed/xHCI)';
          end;

          var PInfo: ^TUSBDeviceInfo; New(PInfo); PInfo^ := Info; List.Add(PInfo);
        end;
      end;
    except
      on E: Exception do EL('Помилка сканування USB-пам''яті: ' + E.Message);
    end;
    SetLength(Result, List.Count);
    for var i := 0 to List.Count - 1 do begin Result[i] := TUSBDeviceInfo(List[i]^); Dispose(List[i]); end;
  finally List.Free; CoUninitialize; end;
end;

procedure TUSBMonitor.WndProc(var Msg: TMessage);
begin
  if (Msg.WParam = DBT_DEVICEARRIVAL) or (Msg.WParam = DBT_DEVICEREMOVECOMPLETE) then
  begin
    var Header := PDevBroadcastHeader(Msg.LParam);
    if (Header <> nil) and (Header^.dbch_devicetype = DBT_DEVTYP_DEVICEINTERFACE) then
    begin
      var IsAdded := (Msg.WParam = DBT_DEVICEARRIVAL);

      if IsAdded then Inc(FConnectionCount) else Inc(FDisconnectionCount);

      LL(Format('🔍 WinAPI: %s (Всього за сеанс: Підключень=%d, Відключень=%d)',
        [IfThen(IsAdded, 'Фізичне підключення USB', 'Фізичне від''єднання USB'), FConnectionCount, FDisconnectionCount]));

      // 🛡️ НАДТОЧНИЙ ЛІКУВАЛЬНИК ЦИКЛІВ ЧЕРЕЗ TICK COUNTER
      if FLastEventTime > 0 then
      begin
        // Рахуємо точний час у мілісекундах від попередньої події
        var ElapsedMS := GetElapsedMS(FLastEventTime);

        // Якщо залізо спамить частіше ніж раз на 1.5 секунди (1500 мс)
        if ElapsedMS < 1500.0 then
        begin
          // Якщо це триває вже більше 4 кроків і блок ще не стоїть
          if (FConnectionCount > 4) and (not FAutoStartBlocked) then
          begin
            FAutoStartBlocked := True;

            // Виводимо велике, помітне попередження в лог
            LL('🚨 ======================================================== 🚨');
            LL('🚨 АЛАРМ: ОПЕРАЦІЙНА СИСТЕМА УВІЙШЛА В НЕСКІНЧЕННИЙ ЦИКЛ USB!');
            LL(Format('🚨 ІНТЕРВАЛ МІЖ ЗБОЯМИ: %s (Критичний ліміт < 1500 мс)', [FormatFloat('0.00 мс', ElapsedMS)]));
            LL('🚨 ПРИЧИНА: Аварійне просідання живлення USB-контролера або дефект кабелю.');
            LL('🚨 АВТОМАТИКА ЗАБЛОКОВАНА ДЛЯ ЗАХИСТУ IDE ТА СИСТЕМИ.');
            LL('🚨 Переставте приймач у стабільний чорний порт USB 2.0.');
            LL('🚨 ======================================================== 🚨');
          end;
        end;
      end;

      // Фіксуємо поточний високоточний такт процесора процесу для наступного кроку
      FLastEventTime := StartTiming;

      // Якщо лікувальник активував блок — миттєво відсікаємо важкі апаратні потік USB
      if FAutoStartBlocked then Exit;

      // Якщо все нормально, виконуємо штатне відновлення
      TThread.CreateAnonymousThread(procedure
        begin
          if IsAdded then Sleep(1500) else Sleep(200);
          var FoundDevices := ScanUSBBus;

          TThread.Queue(nil, procedure
            begin
              if Assigned(FOnUSBEvent) then
              begin
                if IsAdded and (Length(FoundDevices) > 0) then
                begin
                  FOnUSBEvent(FoundDevices[0], True);
                end
                else if not IsAdded then
                begin
                  var EmptyInfo: TUSBDeviceInfo;
                  EmptyInfo.DeviceName := 'RTL-SDR Приймач';
                  FOnUSBEvent(EmptyInfo, False);
                end;
              end;
            end);
        end).Start;
    end;
  end;
end;

end.

