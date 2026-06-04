unit uStopwatch;

interface

uses
  System.SysUtils,
  Winapi.Windows;

type
  TPrecisionTime = Int64;

function StartTiming: TPrecisionTime;
function GetElapsedMS(const StartTime: TPrecisionTime): Double;
function GetElapsedString(const StartTime: TPrecisionTime): string;
procedure PrecisionSleep(Milliseconds: Double);

implementation

var
  F_Frequency: Int64;

function StartTiming: TPrecisionTime;
begin
  QueryPerformanceCounter(Result);
end;

function GetElapsedMS(const StartTime: TPrecisionTime): Double;
begin
  var EndTime: Int64;
  QueryPerformanceCounter(EndTime);
  if F_Frequency > 0 then
    Result := ((EndTime - StartTime) * 1000.0) / F_Frequency
  else
    Result := 0.0;
end;

// јƒјѕ“»¬Ќ≈ ‘ќ–ћј“”¬јЌЌя „ј—” ƒЋя Ћёƒ»Ќ»
function GetElapsedString(const StartTime: TPrecisionTime): string;
begin
  var TotalMS := GetElapsedMS(StartTime);

  // 1. ћенше 1 м≥л≥секунди -> показуЇмо в м≥кросекундах (2 знаки)
  if TotalMS < 1.0 then
  begin
    Result := Format('%.2f мкс', [TotalMS * 1000.0]);
    Exit;
  end;

  // 2. ¬≥д 1 до 10 м≥л≥секунд -> показуЇмо 2 знаки п≥сл€ коми
  if TotalMS < 10.0 then
  begin
    Result := Format('%.2f мс', [TotalMS]);
    Exit;
  end;

  // 3. ¬≥д 10 до 100 м≥л≥секунд -> показуЇмо 1 знак п≥сл€ коми
  if TotalMS < 100.0 then
  begin
    Result := Format('%.1f мс', [TotalMS]);
    Exit;
  end;

  // 4. ¬≥д 100 до 1000 м≥л≥секунд -> округлюЇмо до ц≥лого числа (0 знак≥в)
  if TotalMS < 1000.0 then
  begin
    Result := Format('%.0f мс', [TotalMS]);
    Exit;
  end;

  // ѕереводимо в секунди дл€ великих ≥нтервал≥в
  var TotalSeconds := TotalMS / 1000.0;

  // 5. ¬≥д 1 до 60 секунд -> показуЇмо секунди з 2 знаками
  if TotalSeconds < 60.0 then
  begin
    Result := Format('%.2f сек', [TotalSeconds]);
    Exit;
  end;

    // 6. Ѕ≥льше хвилини -> розбиваЇмо на дн≥, години, хвилини та секунди
  var TotalMinutes := Trunc(TotalSeconds / 60);
  var Secs := Frac(TotalSeconds / 60) * 60;

  if TotalMinutes < 60 then
  begin
    Result := Format('%d хв %.0f сек', [TotalMinutes, Secs]);
  end
  else
  begin
    var TotalHours := TotalMinutes div 60;
    var Mins := TotalMinutes mod 60;

    // якщо менше доби (24 годин)
    if TotalHours < 24 then
    begin
      Result := Format('%d год %d хв', [TotalHours, Mins]);
    end
    else
    begin
      // якщо програма працювала к≥лька д≥б
      var Days := TotalHours div 24;
      var Hours := TotalHours mod 24;
      Result := Format('%d д≥б %d год %d хв', [Days, Hours, Mins]);
    end;
  end;

end;

procedure PrecisionSleep(Milliseconds: Double);
begin
  if Milliseconds <= 0 then Exit;
  var Start, Curr, TargetTicks: Int64;
  QueryPerformanceCounter(Start);
  TargetTicks := Start + Round((Milliseconds * F_Frequency) / 1000.0);
  if Milliseconds > 5.0 then
    Sleep(Round(Milliseconds - 4.0));
  repeat
    QueryPerformanceCounter(Curr);
  until Curr >= TargetTicks;
end;

initialization
  if not QueryPerformanceFrequency(F_Frequency) then
    F_Frequency := 0;

end.

