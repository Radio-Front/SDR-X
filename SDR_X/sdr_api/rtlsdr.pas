unit rtlsdr;

interface

uses
  System.SysUtils,
  Winapi.Windows, // Необхідно для LoadLibrary та GetProcAddress
  System.Hash, // 👈 Необхідно для обчислення SHA-256
  uStopwatch;

type
  Prtlsdr_dev_t = Pointer;

  // 1. Визначаємо типи функцій (прототипи) відповідно до C-стандарту cdecl
  T_rtlsdr_get_device_count = function: Cardinal; cdecl;
  T_rtlsdr_get_device_name = function(index: Cardinal): PAnsiChar; cdecl;
  T_rtlsdr_open = function(var dev: Prtlsdr_dev_t; index: Cardinal): Integer; cdecl;
  T_rtlsdr_close = function(dev: Prtlsdr_dev_t): Integer; cdecl;
  T_rtlsdr_set_center_freq = function(dev: Prtlsdr_dev_t; freq: Cardinal): Integer; cdecl;
  T_rtlsdr_set_sample_rate = function(dev: Prtlsdr_dev_t; rate: Cardinal): Integer; cdecl;
  T_rtlsdr_set_tuner_gain_mode = function(dev: Prtlsdr_dev_t; manual: Integer): Integer; cdecl;
  T_rtlsdr_set_tuner_gain = function(dev: Prtlsdr_dev_t; gain: Integer): Integer; cdecl;
  T_rtlsdr_reset_buffer = function(dev: Prtlsdr_dev_t): Integer; cdecl;
  T_rtlsdr_read_sync = function(dev: Prtlsdr_dev_t; buf: Pointer; len: Integer; var n_read: Integer): Integer; cdecl;
  T_rtlsdr_read_async_cb = procedure(buf: Pointer; len: Cardinal; ctx: Pointer); cdecl;
  T_rtlsdr_read_async = function(dev: Prtlsdr_dev_t; cb: T_rtlsdr_read_async_cb; ctx: Pointer; buf_num: Cardinal; buf_len: Cardinal): Integer; cdecl;
  T_rtlsdr_cancel_async = function(dev: Prtlsdr_dev_t): Integer; cdecl;

var
  // 2. Глобальні змінні-вказівники, через які ми будемо викликати функції
  rtlsdr_get_device_count: T_rtlsdr_get_device_count = nil;
  rtlsdr_get_device_name: T_rtlsdr_get_device_name = nil;
  rtlsdr_open: T_rtlsdr_open = nil;
  rtlsdr_close: T_rtlsdr_close = nil;
  rtlsdr_set_center_freq: T_rtlsdr_set_center_freq = nil;
  rtlsdr_set_sample_rate: T_rtlsdr_set_sample_rate = nil;
  rtlsdr_set_tuner_gain_mode: T_rtlsdr_set_tuner_gain_mode = nil;
  rtlsdr_set_tuner_gain: T_rtlsdr_set_tuner_gain = nil;
  rtlsdr_reset_buffer: T_rtlsdr_reset_buffer = nil;
  rtlsdr_read_sync: T_rtlsdr_read_sync = nil;
  rtlsdr_read_async: T_rtlsdr_read_async = nil;
  rtlsdr_cancel_async: T_rtlsdr_cancel_async = nil;

// Функції керування життєвим циклом DLL
function LoadRTLSRD(const DLLPath: string = 'rtlsdr.dll'): Boolean;
procedure UnloadRTLSRD;
function IsSDRLibraryLoaded: Boolean;

implementation

uses uLogger;

var
  F_DLLHandle: HMODULE = 0; // Хендл завантаженої бібліотеки

  // ОГОЛОШУЄМО ЕТАЛОННІ ХЭШІ ДЛЯ ОБОХ АРХІТЕКТУР
const
  {$IFDEF WIN64}
  // Еталони для 64-бітної версії (замініть на ваші реальні хэші)
  EXPECTED_HASH_RTLSDR = 'DC477674516658819A9DC44804732E8DA89E9D29031C5EDEED88CBA1BAD32AC8';
  EXPECTED_HASH_LIBUSB = '373F0AE78C7A1D60A10403A6EEB4E6497A50262AA6DDC5402D822D044FEA890A';
  {$ELSE}
  // Еталони для 32-бітної версії (замініть на ваші реальні хэші)
  EXPECTED_HASH_RTLSDR = 'B94F48CD2C27A785020242C027BDC1FB68A248B4CA26A73A4B5A9481D97790AF';
  EXPECTED_HASH_LIBUSB = 'D7EE21A056B0EC2EBAFF7A13824B0A4E5C3E7A7A94AB47B47B6B251C56999992';
  {$ENDIF}

function IsSDRLibraryLoaded: Boolean;
begin
  Result := F_DLLHandle <> 0;
end;

// Функція внутрішньої перевірки цілісності файлу
function VerifyFileIntegrity(const FilePath: string; const ExpectedHash: string): Boolean;
begin
    Result := False;
  if not FileExists(FilePath) then Exit;

  try
    // Офіційний метод у Delphi 13.1 для отримання хэшу файлу
    // Параметр TSHA2Version.SHA256 вказує тип алгоритму
    var FileHash := THashSHA2.GetHashStringFromFile(FilePath, THashSHA2.TSHA2Version.SHA256);

    // Порівнюємо результат із нашим еталоном (ігноруючи регістр літер)
    Result := SameText(FileHash, ExpectedHash);
  except
    on E: Exception do
      LL('Помилка криптографічного аналізу файлу: ' + E.Message);
  end;
end;

function LoadRTLSRD(const DLLPath: string): Boolean;
begin
  Result := False;
  if F_DLLHandle <> 0 then Exit(True);

  // ⏱️ ЗАМІР 1: КРИПТОГРАФІЯ (SHA-256)
  var CryptoTimer := StartTiming;

  var LibUsbPath := ExtractFilePath(ParamStr(0)) + 'libusb-1.0.dll';
  if not VerifyFileIntegrity(LibUsbPath, EXPECTED_HASH_LIBUSB) then
  begin
    LL('КРИТИЧНА ПОМИЛКА: libusb-1.0.dll підмінена!');
    Exit(False);
  end;

  var FullDLLPath := ExtractFilePath(ParamStr(0)) + DLLPath;
  if not VerifyFileIntegrity(FullDLLPath, EXPECTED_HASH_RTLSDR) then
  begin
    LL('КРИТИЧНА ПОМИЛКА: rtlsdr.dll підмінена!');
    Exit(False);
  end;

  LL(Format('-> [Етап 1]: Криптографічна перевірка SHA-256 обох DLL тривала %s.', [GetElapsedString(CryptoTimer)]));

  // ⏱️ ЗАМІР 2: ЗАВАНТАЖЕННЯ ОС ТА ЛІНКУВАННЯ ФУНКЦІЙ
  var LinkTimer := StartTiming;

  F_DLLHandle := SafeLoadLibrary(FullDLLPath);
  if F_DLLHandle = 0 then Exit(False);

  @rtlsdr_get_device_count    := GetProcAddress(F_DLLHandle, 'rtlsdr_get_device_count');
  @rtlsdr_get_device_name     := GetProcAddress(F_DLLHandle, 'rtlsdr_get_device_name');
  @rtlsdr_open                := GetProcAddress(F_DLLHandle, 'rtlsdr_open');
  @rtlsdr_close               := GetProcAddress(F_DLLHandle, 'rtlsdr_close');
  @rtlsdr_set_center_freq     := GetProcAddress(F_DLLHandle, 'rtlsdr_set_center_freq');
  @rtlsdr_set_sample_rate     := GetProcAddress(F_DLLHandle, 'rtlsdr_set_sample_rate');
  @rtlsdr_set_tuner_gain_mode := GetProcAddress(F_DLLHandle, 'rtlsdr_set_tuner_gain_mode');
  @rtlsdr_set_tuner_gain      := GetProcAddress(F_DLLHandle, 'rtlsdr_set_tuner_gain');
  @rtlsdr_reset_buffer        := GetProcAddress(F_DLLHandle, 'rtlsdr_reset_buffer');
  @rtlsdr_read_sync           := GetProcAddress(F_DLLHandle, 'rtlsdr_read_sync');
  @rtlsdr_read_async   := GetProcAddress(F_DLLHandle, 'rtlsdr_read_async');
  @rtlsdr_cancel_async := GetProcAddress(F_DLLHandle, 'rtlsdr_cancel_async');

  if Assigned(rtlsdr_get_device_count) and Assigned(rtlsdr_open) and Assigned(rtlsdr_close) then
  begin
    LL(Format('-> [Етап 2]: Завантаження DLL операційною системою та лінкування функцій тривало %s.', [GetElapsedString(LinkTimer)]));
    Result := True;
  end
  else
    UnloadRTLSRD;
end;


procedure UnloadRTLSRD;
begin
  if F_DLLHandle <> 0 then
  begin
    FreeLibrary(F_DLLHandle);
    F_DLLHandle := 0;
  end;

  // Скидаємо вказівники в nil, щоб уникнути помилок Access Violation
  @rtlsdr_get_device_count    := nil;
  @rtlsdr_get_device_name     := nil;
  @rtlsdr_open                := nil;
  @rtlsdr_close               := nil;
  @rtlsdr_set_center_freq     := nil;
  @rtlsdr_set_sample_rate     := nil;
  @rtlsdr_set_tuner_gain_mode := nil;
  @rtlsdr_set_tuner_gain      := nil;
  @rtlsdr_reset_buffer        := nil;
  @rtlsdr_read_sync           := nil;
  @rtlsdr_read_async   := nil;
  @rtlsdr_cancel_async := nil;
end;

initialization
// Початковий стан при старті програми
F_DLLHandle := 0;

finalization
// Автоматично вивантажуємо з пам'яті перед закриттям програми
UnloadRTLSRD;

end.

