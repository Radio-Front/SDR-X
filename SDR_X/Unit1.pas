unit Unit1;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,
  FMX.Controls.Presentation, FMX.Memo.Types, FMX.ScrollBox, FMX.Memo, FMX.Edit,
  FMX.ListBox,
  System.IniFiles,
  System.StrUtils,
  uLogger,       // Модуль логування (LL, EL)
  uStopwatch,    // Високоточний таймер
  uSDRDevice,    // Абстракція SDR
  uSDRManager,   // Контролер станів та курсору
  uUtils,        // Утиліти (GetBitness, AppIni)
  uRTLSDRDevice, // Реалізація чипа RTL-SDR
  uUSBMonitor,   // Монітор USB портів Windows
  uFormStorage;  // CSV-збереження вікон

type
  TForm1 = class(TForm)
    Memo1: TMemo;
    ComboBox1: TComboBox;
    SpeedButton1: TSpeedButton;
    SpeedButton2: TSpeedButton;
    Edit1: TEdit;
    Button4: TButton;
    Button5: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure SpeedButton1Click(Sender: TObject);
    procedure SpeedButton2Click(Sender: TObject);
    procedure ComboBox1Change(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FSDRManager: TSDRManager;
    FUSBMonitor: TUSBMonitor;
    FIsInitializing: Boolean;
    FAppStartTicks: TPrecisionTime;

    procedure GlobalExceptionHandler(Sender: TObject; E: Exception);
    procedure OnLogReceived(const LogLine: string);
    procedure OnIQDataCaptured(const Buffer: TIQBuffer);
    procedure OnUSBHardwareChanged(const Device: TUSBDeviceInfo; const IsAdded: Boolean);
    procedure SetUIEnabled(const AEnabled: Boolean);
    function LoadSettings: string;
    procedure SaveSettings(const DeviceName: string);
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.fmx}

{ TForm1 }

// 1. НАЙПЕРШИЙ КРОК ПРОГРАМИ (До появи вікна на екрані)
procedure TForm1.FormCreate(Sender: TObject);
begin
  // Ініціалізуємо логгер та перехоплювач помилок
  InitLogger(OnLogReceived);
  Application.OnException := GlobalExceptionHandler;

  // ГАРАНТОВАНО НАЙПЕРШИЙ ЗАПИС: Фіксуємо старт на початку процесу
  LL(Format('Старт програми SDR-X %d', [GetBitness]));

  // Ініціалізуємо глобальну конфігурацію OLE/INI
  InitAppConfig;

  // Завантажуємо геометрію вікна з лімітами (Ширина=340, Висота=180)
  LoadFormGeometry(Self, 340, 180);
end;

// Безшумний перехоплювач Access Violation / EListError (Пише у лог з маркером [!])
procedure TForm1.GlobalExceptionHandler(Sender: TObject; E: Exception);
begin
  EL('СИСТЕМНИЙ ЗБІЙ (Перехоплено): ' + E.Message);
end;

procedure TForm1.OnIQDataCaptured(const Buffer: TIQBuffer);
begin
  // Сюди асинхронно летять пакети радіобайтів для майбутнього DSP ядра
end;

procedure TForm1.SetUIEnabled(const AEnabled: Boolean);
begin
  SpeedButton1.Enabled := AEnabled;
  SpeedButton2.Enabled := AEnabled;
  ComboBox1.Enabled := AEnabled;
  Button4.Enabled := AEnabled;
end;

// 2. ВІКНО НА СВОЄМУ МІСЦІ: Запуск асинхронних фонових потоків заліза
procedure TForm1.FormShow(Sender: TObject);
begin
  FAppStartTicks := StartTiming;
  Self.Caption := Format('SDR-X %d', [GetBitness]);

  FSDRManager := TSDRManager.Create(OnIQDataCaptured);
  FUSBMonitor := TUSBMonitor.Create(OnUSBHardwareChanged);

  FIsInitializing := True;
  SetUIEnabled(False);

  TThread.CreateAnonymousThread(procedure
    begin
      // Чекаємо OLE WMI потік, щоб чіпсети материнки прописалися раніше за етапи SDR
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

          LL(Format('-> [Етап 3]: Физичне сканування USB-шини драйвером тривало %s.', [HardwareScanDuration]));

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

              var RestoredFreq: Integer;
              if TryStrToInt(Edit1.Text, RestoredFreq) then
              begin
                if FSDRManager.ChangeFrequency(RestoredFreq) then
                  LL(Format('Автоматично відновлено робочу частоту: %n Гц', [RestoredFreq * 1.0]));
              end;

              LL(Format('Приймач успішно підключено у фоновому режимі за %s від старту програми.', [GetElapsedString(FAppStartTicks)]));
            end;
          end
          else
          begin
            // 🛡️ Використовуємо марковану процедуру помилок EL
            EL('УВАГА: Жодного апаратного приймача RTL-SDR не виявлено на USB-шині!');
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

// АВТОМАТИЧНЕ ГАРЯЧЕ ПЕРЕПІДКЛЮЧЕННЯ ШНУРА USB
procedure TForm1.OnUSBHardwareChanged(const Device: TUSBDeviceInfo; const IsAdded: Boolean);
begin
  if IsAdded then
  begin
    LL(Format('🔔 ВИЯВЛЕНО ГАРЯЧЕ ПІДКЛЮЧЕННЯ: %s', [Device.DeviceName]));
    LL(Format('   -> Апаратні ключі: VID_%s & PID_%s', [Device.VID, Device.PID]));
    LL(Format('   -> Фізична топологія: Підключено в апаратне гніздо (Порт №%d)', [Device.PortNumber]));
    LL(Format('   -> Швидкість інтерфейсу контролера: %s', [Device.USBVersion]));
    LL('🚀 Запуск автоматичного відновлення радіопотоку...');

    // Імітуємо натискання кнопки оновлення
    SpeedButton1Click(nil);
  end
  else
  begin
    LL('📴 СИГНАЛ: USB-кабель приймача фізично витягнуто з гнізда комп''ютера.');
  end;
end;

// КНОПКА 1: Оновлення списку та повернення до поточного залізяччя
procedure TForm1.SpeedButton1Click(Sender: TObject);
begin
  SetUIEnabled(False);
  FIsInitializing := True; // Блокуємо авто-зміни ComboBox
  LL('Ручне оновлення списку приймачів після гарячого підключення...');

  TThread.CreateAnonymousThread(procedure
    begin
      FSDRManager.Disconnect;
      Sleep(200);

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

            TThread.CreateAnonymousThread(procedure
              begin
                if FSDRManager.ConnectTo(TargetIdx, ComboBox1.Items[TargetIdx]) then
                begin
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
            EL('УВАГА: Пристрій не встиг ініціалізуватися на шині USB.');
            ComboBox1.ItemIndex := -1;
            FIsInitializing := False;
            SetUIEnabled(True);
          end;
        end);
    end).Start;
end;

// КНОПКА 2: Примусове перепідключення + скидання захисних лічильників спаму
procedure TForm1.SpeedButton2Click(Sender: TObject);
begin
  if ComboBox1.ItemIndex < 0 then Exit;

  SetUIEnabled(False);
  FIsInitializing := True;
  LL('Примусове перепідключення поточного пристрою...');

  if Assigned(FUSBMonitor) then
    FUSBMonitor.ResetSessionCounters;

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

// КОРИСТУВАЧ ЗМІНИВ ЕЛЕМЕНТ У СПИСКУ ВРУЧНУ
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

// РУЧНА ЗМІНА ЧАСТОТИ ТЮНЕРА (Button4)
procedure TForm1.Button4Click(Sender: TObject);
begin
  var Freq: Integer;
  if TryStrToInt(Edit1.Text, Freq) then
  begin
    if FSDRManager.ChangeFrequency(Freq) then
    begin
      LL(Format('Частоту змінено на: %n Гц', [Freq * 1.0]));
      SaveSettings('');
    end
    else
      EL('Залізо відхилило встановлення цієї частоти.');
  end
  else
    EL('Помилка введення частоти: введіть ціле число в Гц!');
end;

// ЗЧИТУВАННЯ РАДІОНАЛАШТУВАНЬ З ГЛОБАЛЬНОГО INI
function TForm1.LoadSettings: string;
begin
  Result := '';
  if AppIni = nil then Exit;
  Result := AppIni.ReadString('SDR', 'LastDeviceName', '');
  var LastFreq := AppIni.ReadInteger('SDR', 'LastFrequencyHz', 100000000);
  Edit1.Text := LastFreq.ToString;
end;

// ЗБЕРЕЖЕННЯ РАДІОНАЛАШТУВАНЬ У ГЛОБАЛЬНИЙ INI
procedure TForm1.SaveSettings(const DeviceName: string);
begin
  if AppIni = nil then Exit;
  if DeviceName <> '' then
    AppIni.WriteString('SDR', 'LastDeviceName', DeviceName);

  var CurrentFreq: Integer;
  if TryStrToInt(Edit1.Text, CurrentFreq) then
    AppIni.WriteInteger('SDR', 'LastFrequencyHz', CurrentFreq);
end;

// CALLBACK: Виведення сформованого тексту логгера у Memo1
procedure TForm1.OnLogReceived(const LogLine: string);
begin
  Memo1.Lines.Add(LogLine);
end;

// ПОДІЯ: Руйнування форми та фіксація конфігурацій перед виходом
procedure TForm1.FormDestroy(Sender: TObject);
begin
  SetUIEnabled(False);

  // Універсальне збереження форми в один CSV рядок через модуль uFormStorage
  SaveFormGeometry(Self);

  // Зберігаємо частоту та пристрій у глобальний INI
  SaveSettings('');

  // Безпечно гасимо фонові потоки
  if Assigned(FUSBMonitor) then FreeAndNil(FUSBMonitor);
  if Assigned(FSDRManager) then FreeAndNil(FSDRManager);

  var TotalWorkTimeStr := GetElapsedString(FAppStartTicks);
  LL(Format('Загальний час роботи програми: %s', [TotalWorkTimeStr]));
  LL('Завершення програми');
end;

end.


