unit Unit1;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,
  FMX.Controls.Presentation, FMX.Memo.Types, FMX.ScrollBox, FMX.Memo, FMX.Edit,
  FMX.ListBox, System.IniFiles, System.StrUtils,
  uLogger, uStopwatch, uUtils, uSDRDevice,
  uSDRManager,uRTLSDRDevice, uUSBMonitor, uFormStorage;

type
  TForm1 = class(TForm)
    Memo1: TMemo;
    Panel1: TPanel;
    ComboBox1: TComboBox;
    SpeedButton1: TSpeedButton;
    Edit1: TEdit;
    Button4: TButton;
    Button5: TButton;
    SpeedButton2: TSpeedButton;
    procedure SpeedButton1Click(Sender: TObject);
    procedure SpeedButton2Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure ComboBox1Change(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FSDRManager: TSDRManager;   // 👈 Керування йде суто через цей об'єкт
    FIsInitializing: Boolean;
    FAppStartTicks: TPrecisionTime;
    FUSBMonitor: TUSBMonitor;

    procedure OnLogReceived(const LogLine: string);
    procedure OnIQDataCaptured(const Buffer: TIQBuffer);
    procedure SetUIEnabled(const AEnabled: Boolean);
    function LoadSettings: string;
    procedure SaveSettings(const DeviceName: string);
    procedure GlobalExceptionHandler(Sender: TObject; E: Exception);
    procedure OnUSBHardwareChanged(const Device: TUSBDeviceInfo; const IsAdded: Boolean);
  end;

var
  Form1: TForm1;

implementation

{$R *.fmx}

{ TForm1 }

// ГОЛОВНИЙ АВТОМАТ ДЛЯ ГАРЯЧОГО ПЕРЕПІДКЛЮЧЕННЯ ЗАЛІЗА
procedure TForm1.OnUSBHardwareChanged(const Device: TUSBDeviceInfo; const IsAdded: Boolean);
begin
  if IsAdded then
  begin
    LL(Format('🔔 ВИЯВЛЕНО ГАРЯЧЕ ПІДКЛЮЧЕННЯ: %s', [Device.DeviceName]));
    LL(Format('   -> Апаратні ключі: VID_%s & PID_%s', [Device.VID, Device.PID]));
    LL(Format('   -> Фізична топологія: Підключено в апаратне гніздо (Порт №%d)', [Device.PortNumber]));
    LL(Format('   -> Швидкість інтерфейсу контролера: %s', [Device.USBVersion]));
    LL('🚀 Запуск автоматичного відновлення радіопотоку...');

    // Викликаємо оновлення та старт ефіру
    SpeedButton1Click(nil);
  end
  else
  begin
    LL('📴 СИГНАЛ: USB-кабель приймача фізично витягнуто з гнізда комп''ютера.');
  end;
end;


procedure TForm1.OnIQDataCaptured(const Buffer: TIQBuffer);
begin
  // Сюди летять сирі IQ дані для DSP
end;

// Блокування кнопок на час виконання операцій із залізом
procedure TForm1.SetUIEnabled(const AEnabled: Boolean);
begin
  SpeedButton1.Enabled := AEnabled;
  SpeedButton2.Enabled := AEnabled;
  ComboBox1.Enabled := AEnabled;
  Button4.Enabled := AEnabled;
end;

// Реалізація безшумного логування помилок
procedure TForm1.GlobalExceptionHandler(Sender: TObject; E: Exception);
begin
  // Замість показу вікна користувачу — просто тихо пишемо у наш log-файл
  LL('🚨 СИСТЕМНИЙ ЗБІЙ (Перехоплено): ' + E.Message);
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  FAppStartTicks := StartTiming;
  Self.Caption := Format('SDR-X %d', [GetBitness]);

  // 🛡️ ВИПРАВЛЕНО: Рядок "Старт програми" звідси видалено, щоб уникнути дублювання та зміщення хронології

  FSDRManager := TSDRManager.Create(OnIQDataCaptured);
  FUSBMonitor := TUSBMonitor.Create(OnUSBHardwareChanged);

  FIsInitializing := True;
  SetUIEnabled(False);

  // Далі йде фоновий потік аналізу швидкодії заліза (без змін)...

  TThread.CreateAnonymousThread(procedure
    begin
      // Чекаємо WMI потік монітора, щоб лог контролерів був першим
      var SafeTimeout := 0;
      while (not FUSBMonitor.ControllersCounted) and (SafeTimeout < 50) do
      begin
        Sleep(10);
        Inc(SafeTimeout);
      end;

      LL('Фоновий потік: Аналіз швидкодії запуска...');

      var HardwareScanTimer := StartTiming;
      var FoundList := ScanRTLSDR;
      var HardwareScanDuration := GetElapsedString(HardwareScanTimer);

      TThread.Queue(nil, procedure
        begin
          ComboBox1.Clear;
          ComboBox1.Items.Assign(FoundList);
          FoundList.Free;

          LL(Format('-> [Етап 3]: Фізичне сканування USB-шини драйвером тривало %s.', [HardwareScanDuration]));

          var SavedDevName := LoadSettings();
          var TargetIndex := -1;

          if ComboBox1.Items.Count > 0 then
          begin
            TargetIndex := 0;
            if SavedDevName <> '' then
            begin
              for var i := 0 to ComboBox1.Items.Count - 1 do
              begin
                if Pos(SavedDevName, ComboBox1.Items[i]) > 0 then
                begin
                  TargetIndex := i;
                  LL('Знайдено збережений пристрій з минулої сесії: ' + SavedDevName);
                  Break;
                end;
              end;
            end;

            ComboBox1.ItemIndex := TargetIndex;
            FIsInitializing := False;

            var ConfigAndConnectTimer := StartTiming;
            if FSDRManager.ConnectTo(TargetIndex, ComboBox1.Items[TargetIndex]) then
            begin
              var ConfigAndConnectDuration := GetElapsedString(ConfigAndConnectTimer);
              LL(Format('-> [Етап 4]: Апаратне відкриття/налаштування пристрою тривало %s.', [ConfigAndConnectDuration]));
              LL(Format('Приймач успішно підключено у фоновому режимі за %s від старту програми.', [GetElapsedString(FAppStartTicks)]));
            end;
          end
          else
          begin
            LL('УВАГА: Жодного апаратного приймача RTL-SDR не виявлено на USB-шині!');
            if SavedDevName <> '' then
              LL('Збережений у конфігурації пристрій [' + SavedDevName + '] зараз відключений.');

            LL('Програма SDR-X переведена в автономний режим роботи.');
            ComboBox1.ItemIndex := -1;
            FIsInitializing := False;
          end;

          SetUIEnabled(True);
        end);
    end).Start;
end;


// КНОПКА 1: Оновлення списку та повернення до поточного пристрою
procedure TForm1.SpeedButton1Click(Sender: TObject);
begin
  SetUIEnabled(False);
  FIsInitializing := True; // Блокуємо авто-зміни ComboBox
  LL('Ручне оновлення списку приймачів після гарячого підключення...');

  TThread.CreateAnonymousThread(procedure
    begin
      // Повністю звільняємо залізо перед новим пошуком
      FSDRManager.Disconnect;
      Sleep(200);

      // Викликаємо швидке сканування через чисту бібліотеку rtlsdr
      var TargetIdx: Integer;
      var FoundList := FSDRManager.ScanAndRestore(TargetIdx);

      TThread.Queue(nil, procedure
        begin
          ComboBox1.Clear;
          ComboBox1.Items.Assign(FoundList);
          FoundList.Free;

          if ComboBox1.Items.Count > 0 then
          begin
            ComboBox1.ItemIndex := TargetIdx;

            // Запускаємо підключення у фоні
            TThread.CreateAnonymousThread(procedure
              begin
                if FSDRManager.ConnectTo(TargetIdx, ComboBox1.Items[TargetIdx]) then
                begin
                  // Автоматично відновлюємо останню частоту після гарячого перепідключення!
                  var RestoredFreq: Integer;
                  if TryStrToInt(Edit1.Text, RestoredFreq) then
                    FSDRManager.ChangeFrequency(RestoredFreq);
                end;

                TThread.Queue(nil, procedure
                  begin
                    FIsInitializing := False;
                    SetUIEnabled(True);
                  end);
              end).Start;
          end
          else
          begin
            LL('УВАГА: Пристрій не встиг ініціалізуватися. Спробуйте оновити ще раз.');
            ComboBox1.ItemIndex := -1;
            FIsInitializing := False;
            SetUIEnabled(True);
          end;
        end);
    end).Start;
end;

// КНОПКА 2: Тільки ПЕРЕПІДКЛЮЧЕННЯ до поточного вибраного пристрою
procedure TForm1.SpeedButton2Click(Sender: TObject);
begin
  if ComboBox1.ItemIndex < 0 then Exit;

  SetUIEnabled(False);
  FIsInitializing := True; // Блокуємо авто-зміни
  LL('Примусове перепідключення поточного пристрою...');

  TThread.CreateAnonymousThread(procedure
    begin
      FSDRManager.ConnectTo(ComboBox1.ItemIndex, ComboBox1.Items[ComboBox1.ItemIndex]);
      TThread.Queue(nil, procedure
        begin
          FIsInitializing := False;
          SetUIEnabled(True);
        end);
    end).Start;
end;

// ВИБІР У СПИСКУ: Миттєво робить підключення до нового вибраного приймача
procedure TForm1.ComboBox1Change(Sender: TObject);
begin
  if FIsInitializing or (ComboBox1.ItemIndex < 0) then Exit;

  SetUIEnabled(False);
  LL('Зміна пристрою через список...');

  TThread.CreateAnonymousThread(procedure
    begin
      var SelectedName := ComboBox1.Items[ComboBox1.ItemIndex];
      if FSDRManager.ConnectTo(ComboBox1.ItemIndex, SelectedName) then
      begin
        SaveSettings(SelectedName);
      end;

      TThread.Queue(nil, procedure
        begin
          SetUIEnabled(True);
        end);
    end).Start;
end;

procedure TForm1.Button4Click(Sender: TObject);
begin
  var Freq: Integer;
  if TryStrToInt(Edit1.Text, Freq) then
  begin
    if FSDRManager.ChangeFrequency(Freq) then
      LL(Format('Частоту змінено на: %n Гц', [Freq * 1.0]));
  end;
end;

// 2. ОНОВЛЕНИЙ МЕТОД LOADSETTINGS: Тепер він зчитує ТІЛЬКИ налаштування заліза
function TForm1.LoadSettings: string;
begin
  Result := '';
  var IniPath := ChangeFileExt(ParamStr(0), '.ini');
  var Ini := TIniFile.Create(IniPath);
  try
    // Зчитуємо тільки радіопараметри, вікно більше не чіпаємо!
    Result := Ini.ReadString('SDR', 'LastDeviceName', '');
    var LastFreq := Ini.ReadInteger('SDR', 'LastFrequencyHz', 100000000);
    Edit1.Text := LastFreq.ToString;
  finally
    Ini.Free;
  end;
end;

procedure TForm1.SaveSettings(const DeviceName: string);
begin
  if AppIni = nil then Exit;

  // 3. Записуємо радіопараметри безпосередньо у глобальний об'єкт AppIni
  if DeviceName <> '' then
    AppIni.WriteString('SDR', 'LastDeviceName', DeviceName);

  var CurrentFreq: Integer;
  if TryStrToInt(Edit1.Text, CurrentFreq) then
    AppIni.WriteInteger('SDR', 'LastFrequencyHz', CurrentFreq);
end;

procedure TForm1.OnLogReceived(const LogLine: string);
begin
  Memo1.Lines.Add(LogLine);
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  // 1. НАЙПЕРШИЙ КРОК ПРОГРАМИ: Ініціалізуємо логгер
  InitLogger(OnLogReceived);
  Application.OnException := GlobalExceptionHandler;

  // 2. ГОЛОВНИЙ ЗАПИС: Фіксуємо старт програми на першому ж мілісекундному такті процесу
  LL(Format('Старт програми SDR-X %d', [GetBitness]));

  // 3. ТРЕТІЙ КРОК: Запускаємо глобальну конфігурацію (INI)
  InitAppConfig;

  // 4. ЧЕТВЕРТИЙ КРОК: Завантажуємо геометрію вікна з динамічними обмеженнями
  LoadFormGeometry(Self, 340, 180);
end;



// 3. ЗБЕРЕЖЕННЯ ГЕОМЕТРІЇ ПЕРЕД ВИХОДОМ
procedure TForm1.FormDestroy(Sender: TObject);
begin
  SetUIEnabled(False);

  // 💾 Викликаємо універсальне збереження форми в один CSV рядок перед виходом
  SaveFormGeometry(Self);

  // Зберігаємо частоту та пристрій
  SaveSettings('');

  if Assigned(FUSBMonitor) then FreeAndNil(FUSBMonitor);
  if Assigned(FSDRManager) then FreeAndNil(FSDRManager);

  var TotalWorkTimeStr := GetElapsedString(FAppStartTicks);
  LL(Format('Загальний час роботи програми: %s', [TotalWorkTimeStr]));
  LL('Завершення програми');
end;
end.

