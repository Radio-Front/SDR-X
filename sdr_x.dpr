program sdr_x;

uses
  System.StartUpCopy,
  FMX.Forms,
  Unit1 in 'Unit1.pas' {Form1},
  rtlsdr in 'sdr_api\rtlsdr.pas',
  uLogger in 'sdr_api\uLogger.pas',
  uStopwatch in 'sdr_api\uStopwatch.pas',
  uSDRDevice in 'sdr_api\uSDRDevice.pas',
  uRTLSDRDevice in 'sdr_api\uRTLSDRDevice.pas',
  uUtils in 'sdr_api\uUtils.pas',
  uSDRManager in 'sdr_api\uSDRManager.pas',
  uUSBMonitor in 'sdr_api\uUSBMonitor.pas',
  uFormStorage in 'sdr_api\uFormStorage.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
