unit uFormStorage;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IniFiles,
  System.UITypes,
  System.Types, // 👈 ПЕРЕВІРТЕ НАЯВНІСТЬ ЦЬОГО МОДУЛЯ СЮДИ!
  FMX.Forms;

procedure SaveFormGeometry(AForm: TForm);

/// <summary>
/// Завантажує геометрію форми з параметрами мінімальних обмежень (за замовчуванням 0 - без обмежень)
/// </summary>
procedure LoadFormGeometry(AForm: TForm; const MinWidth: Integer = 0; const MinHeight: Integer = 0);

implementation

uses
  uLogger,
  uUtils; // 👈 Підключаємо менеджер глобального INI

procedure SaveFormGeometry(AForm: TForm);
var
  L, T, W, H, IsMax: Integer;
  OldCSV: string;
  Tokens: TArray<string>;
  CSVLine: string;
begin
  if (AForm = nil) or (AppIni = nil) then Exit;

  L := Round(AForm.Left);
  T := Round(AForm.Top);
  W := Round(AForm.Width);
  H := Round(AForm.Height);
  IsMax := 0;

  if AForm.WindowState = TWindowState.wsMaximized then
  begin
    IsMax := 1;
    // Працюємо напряму через глобальний AppIni
    OldCSV := AppIni.ReadString('WindowsGeometry', AForm.Name, '');
    if OldCSV <> '' then
    begin
      Tokens := OldCSV.Split([';']);
      if Length(Tokens) >= 5 then
      begin
        TryStrToInt(Tokens[1], L);
        TryStrToInt(Tokens[2], T);
        TryStrToInt(Tokens[3], W);
        TryStrToInt(Tokens[4], H);
      end;
    end;
  end
  else if AForm.WindowState = TWindowState.wsMinimized then
  begin
    Exit;
  end;

  CSVLine := Format('%s;%d;%d;%d;%d;%d', [AForm.Name, L, T, W, H, IsMax]);
  AppIni.WriteString('WindowsGeometry', AForm.Name, CSVLine);
end;

procedure LoadFormGeometry(AForm: TForm; const MinWidth: Integer; const MinHeight: Integer);
var
  L, T, W, H, IsMax: Integer;
  WALeft, WATop, WARight, WABottom: Integer;
  CSVLine: string;
  Tokens: TArray<string>;
  WorkArea: TRectF; // 👈 ПОВЕРНЕНО ПРАВИЛЬНИЙ ТИП ЗБЕРЕЖЕННЯ МЕЖ (З System.Types)
begin
  if (AForm = nil) or (AppIni = nil) then Exit;

  // Застосовуємо мінімальні обмеження форми
  if MinWidth > 0 then AForm.Constraints.MinWidth := MinWidth;
  if MinHeight > 0 then AForm.Constraints.MinHeight := MinHeight;

  CSVLine := AppIni.ReadString('WindowsGeometry', AForm.Name, '');
  if CSVLine = '' then
  begin
    WorkArea := Screen.WorkAreaRect;
    AForm.Left := Round(WorkArea.Left + (WorkArea.Width - AForm.Width) / 2);
    AForm.Top := Round(WorkArea.Top + (WorkArea.Height - AForm.Height) / 2);

    LL(Format('🛡️ Геометрія: Для вікна [%s] застосовано розміри з IDE, задано ліміти та відцентровано.', [AForm.Name]));
    Exit;
  end;

  Tokens := CSVLine.Split([';']);
  if Length(Tokens) < 6 then Exit;

  // Квадратні дужки індексів масиву та чисті Integer
  if not TryStrToInt(Tokens[1], L) then Exit;
  if not TryStrToInt(Tokens[2], T) then Exit;
  if not TryStrToInt(Tokens[3], W) then Exit;
  if not TryStrToInt(Tokens[4], H) then Exit;
  if not TryStrToInt(Tokens[5], IsMax) then Exit;

  // 🛡️ ЗЧИТУЄМО МЕЖІ ЕКРАНА (Миттєво і без помилок)
  WorkArea := Screen.WorkAreaRect;
  WALeft   := Round(WorkArea.Left);
  WATop    := Round(WorkArea.Top);
  WARight  := Round(WorkArea.Right);
  WABottom := Round(WorkArea.Bottom);

  // Перевірка відповідності мінімальним обмеженням
  if (MinWidth > 0) and (W < MinWidth) then W := MinWidth;
  if (MinHeight > 0) and (H < MinHeight) then H := MinHeight;

  if W > Round(WorkArea.Width) then W := Round(WorkArea.Width) - 40;
  if H > Round(WorkArea.Height) then H := Round(WorkArea.Height) - 40;

  if L < WALeft then L := WALeft;
  if T < WATop then T := WATop;
  if (L + W) > WARight then L := WARight - W;
  if (T + H) > WABottom then T := WABottom - H;

  AForm.Width := W;
  AForm.Height := H;
  AForm.Left := L;
  AForm.Top := T;

  if IsMax = 1 then
    AForm.WindowState := TWindowState.wsMaximized;

  LL(Format('🛡️ Геометрія: Для вікна [%s] відновлено конфігурацію із динамічними лімітами.', [AForm.Name]));
end;

end.

