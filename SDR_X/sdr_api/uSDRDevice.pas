unit uSDRDevice;

interface

uses
  System.Classes, System.SysUtils;

type
  // Буфер для передачі сирих IQ-даних
  TIQBuffer = array of Byte;
  TOnIQData = procedure(const Buffer: TIQBuffer) of object;

  // Абстрактний клас - шаблон для будь-якого SDR приймача
  TSDRDevice = class
  protected
    FDeviceIndex: Integer;
    FIsConnected: Boolean;
    FSampleRate: Cardinal;
    FCenterFreq: Cardinal;
    FOnIQDataReceived: TOnIQData;
  public
    constructor Create(const ADeviceIndex: Integer); virtual;
    destructor Destroy; override;

    // Абстрактні методи, які кожен тип SDR повинен реалізувати по-своєму
    function Connect: Boolean; virtual; abstract;
    procedure Disconnect; virtual; abstract;
    function SetCenterFreq(const AFreqHz: Cardinal): Boolean; virtual; abstract;
    function SetSampleRate(const ARateHz: Cardinal): Boolean; virtual; abstract;

    // Властивості (Getters / Setters)
    property IsConnected: Boolean read FIsConnected;
    property DeviceIndex: Integer read FDeviceIndex;
    property CenterFreq: Cardinal read FCenterFreq;
    property SampleRate: Cardinal read FSampleRate;
    property OnIQDataReceived: TOnIQData read FOnIQDataReceived write FOnIQDataReceived;
  end;

// Глобальна функція для сканування (повертає список імен знайдених пристроїв будь-якого типу)
function ScanForSDRDevices: TStringList;

implementation

uses uLogger;

constructor TSDRDevice.Create(const ADeviceIndex: Integer);
begin
  inherited Create;
  FDeviceIndex := ADeviceIndex;
  FIsConnected := False;
  FSampleRate := 2048000;
  FCenterFreq := 100000000;
end;

destructor TSDRDevice.Destroy;
begin
  inherited Destroy;
end;

function ScanForSDRDevices: TStringList;
begin
  Result := TStringList.Create;
  // Ця функція буде розширюватися у майбутньому для опитування всіх DLL (RTL, HackRF тощо)
end;

end.

