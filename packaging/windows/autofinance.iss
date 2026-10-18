; MA-TSK-232. Compile only through scripts/build-windows-installer.ps1.
#if VER != 0x06050400
  #error Inno Setup 6.5.4 required
#endif
#ifndef PackageInclude
  #error PackageInclude must identify the closed, verified payload include
#endif
#include PackageInclude

[Setup]
AppId={{82D31B27-9717-4DB7-AB32-D098BF3C2859}
AppName=Autofinance
AppVersion={#ApplicationVersion}
AppVerName=Autofinance {#ApplicationVersion}
VersionInfoVersion={#WindowsVersion}
VersionInfoProductName=Autofinance
VersionInfoDescription=Instalador privado de Autofinance
DefaultDirName={localappdata}\Programs\Autofinance
UsePreviousAppDir=no
DisableDirPage=yes
PrivilegesRequired=lowest
UsePreviousPrivileges=no
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
DefaultGroupName=Autofinance
DisableProgramGroupPage=yes
AlwaysUsePersonalGroup=yes
UsePreviousGroup=no
CloseApplications=no
RestartApplications=no
AllowCancelDuringInstall=yes
RestartIfNeededByRun=no
AlwaysRestart=no
SetupMutex=Local\AutofinancePrivateSetup-82D31B27-9717-4DB7-AB32-D098BF3C2859
UninstallDisplayName=Autofinance
UninstallDisplayIcon={app}\myautofinance.exe
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
WizardStyle=modern
WizardSizePercent=120,120
WizardResizable=yes
WizardImageFile=
WizardSmallImageFile=
DisableWelcomePage=no
DisableReadyPage=no
DisableFinishedPage=no
Compression=lzma2
SolidCompression=yes
ExtraDiskSpaceRequired=33554432
OutputDir={#PrivateOutput}
OutputBaseFilename=Autofinance-{#ApplicationVersion}-windows-x64-private

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Messages]
spanish.WelcomeLabel1=Instalar Autofinance {#ApplicationVersion}
spanish.WelcomeLabel2=Autofinance se instala solo para tu usuario de Windows 10/11 x64, sin permisos de administrador, SDK ni descargas. Incluye el runtime de C++ en su carpeta.%n%nSe conservan tus datos, copias, diarios y estado Drive. Las migraciones y sus respaldos corresponden a la aplicación al abrirla.%n%nEntrega privada sin firma digital. El SHA-256 permite comparar integridad; no acredita autoría ni confianza de Windows.%n%nCierra Autofinance normalmente antes de continuar y guarda o descarta tus borradores desde la aplicación.
spanish.ConfirmUninstall=¿Desinstalar Autofinance de este usuario?%n%nSe conservarán datos, copias, diarios y estado Drive. Se retirará únicamente la credencial y el marcador locales de esta instalación, sin revocar el acceso remoto.%n%nCierra Autofinance normalmente antes de continuar. Si hay archivos bloqueados, cancela y reintenta.
spanish.UninstalledAll=Autofinance se ha desinstalado. Tus datos, copias, diarios y estado Drive se conservan. Esta instalación se ha desconectado localmente. Para volver a usar Drive tras reinstalar, conecta intencionalmente desde la aplicación.

[Tasks]
Name: "desktopicon"; Description: "Crear un acceso directo en el escritorio (opcional)"; Flags: unchecked

[Icons]
Name: "{userprograms}\Autofinance"; Filename: "{app}\myautofinance.exe"; WorkingDir: "{app}"; AppUserModelID: "com.carlosmg91.Autofinance"
Name: "{userdesktop}\Autofinance"; Filename: "{app}\myautofinance.exe"; WorkingDir: "{app}"; Tasks: desktopicon; AppUserModelID: "com.carlosmg91.Autofinance"

[Run]
Filename: "{app}\myautofinance.exe"; Description: "Abrir Autofinance"; Flags: postinstall unchecked skipifsilent runasoriginaluser; Check: CanLaunch

[Code]
const
  Ready = 0;
  Cleared = 2;
  Busy = 4;
var
  SourcePage: TInputFileWizardPage;
  ConsentPage: TWizardPage;
  ConsentCheck: TNewCheckBox;
  SourceDetails: TNewMemo;
  ConsentIntro: TNewStaticText;
  FixedDestination, Support, PriorVersion, OperationName, VerifiedSource: String;
  Initialized, Active, InstalledOK, CleanupStarted: Boolean;

function HasSwitch(Name: String): Boolean;
var I: Integer; Arg: String;
begin
  Result := False;
  for I := 1 to ParamCount do begin
    Arg := ParamStr(I);
    if Pos('=', Arg) > 0 then Arg := Copy(Arg, 1, Pos('=', Arg) - 1);
    if CompareText(Arg, Name) = 0 then begin Result := True; Exit; end;
  end;
end;

function SafeCommandLine: Boolean;
begin
  Result := not (HasSwitch('/CLOSEAPPLICATIONS') or HasSwitch('/FORCECLOSEAPPLICATIONS') or
    HasSwitch('/RESTARTAPPLICATIONS') or HasSwitch('/NOCANCEL') or HasSwitch('/ALLUSERS'));
  if not Result then SuppressibleMsgBox('Este instalador no admite cierre forzado, relanzamiento, instalación global ni desactivar la cancelación. Retira esos parámetros y cierra Autofinance normalmente.', mbError, MB_OK, IDOK);
end;

function InitializeSetup: Boolean;
begin
  Result := SafeCommandLine;
  if Result and WizardSilent and not HasSwitch('/NORESTART') then begin
    SuppressibleMsgBox('La instalación silenciosa requiere /NORESTART. No se reiniciará Windows automáticamente.', mbError, MB_OK, IDOK);
    Result := False;
  end;
end;

function NativeInitialize(Manifest, Staged: String): Integer;
  external 'AfInitialize@files:autofinance_setup_bridge.dll stdcall delayload setuponly';
function NativeInfo(Field: Cardinal; Buffer: String; Capacity: Cardinal): Integer;
  external 'AfInfo@files:autofinance_setup_bridge.dll stdcall delayload setuponly';
function NativeSource(Source, Buffer: String; Capacity: Cardinal): Integer;
  external 'AfSource@files:autofinance_setup_bridge.dll stdcall delayload setuponly';
function NativeBegin(Source: String): Integer;
  external 'AfBegin@files:autofinance_setup_bridge.dll stdcall delayload setuponly';
function NativeStage: Integer;
  external 'AfStage@files:autofinance_setup_bridge.dll stdcall delayload setuponly';
function NativeCommit: Integer;
  external 'AfCommit@files:autofinance_setup_bridge.dll stdcall delayload setuponly';
function NativeAbort: Integer;
  external 'AfAbort@files:autofinance_setup_bridge.dll stdcall delayload setuponly';
function UninstallBegin(Root: String): Integer;
  external 'AfUninstallBegin@{tmp}\autofinance_setup_bridge.dll stdcall delayload uninstallonly';
function UninstallClean: Integer;
  external 'AfUninstallClean@{tmp}\autofinance_setup_bridge.dll stdcall delayload uninstallonly';
function UninstallFinish: Integer;
  external 'AfUninstallFinish@{tmp}\autofinance_setup_bridge.dll stdcall delayload uninstallonly';
function UninstallAbort: Integer;
  external 'AfAbort@{tmp}\autofinance_setup_bridge.dll stdcall delayload uninstallonly';

function FailureText(Code: Integer): String;
begin
  if Code = 9 then
    Result := 'El paquete Autofinance {#ApplicationVersion} es anterior a una versión instalada o pendiente. Se ha bloqueado la instalación antes de sustituir archivos. Ejecuta el mismo instalador o uno más reciente.'
  else if Code = Busy then
    Result := 'Autofinance o uno de sus archivos está en uso. Cierra la aplicación normalmente, resuelve tus borradores y pulsa Reintentar. No se forzará el cierre.'
  else
    Result := 'No se puede verificar la operación (INSTALL-' + IntToStr(Code) + '). Comprueba versión, destino, permisos, espacio y archivos bloqueados. No elijas otro directorio ni borres datos o marcadores. Reintenta con este instalador o uno más reciente; consulta la guía de recuperación.';
end;

function Info(Field: Cardinal): String;
var Buffer: String;
begin
  SetLength(Buffer, 32768);
  if NativeInfo(Field, Buffer, 32768) <> Ready then RaiseException('INSTALL-INFO');
  Result := Copy(Buffer, 1, Pos(#0, Buffer) - 1);
end;

procedure AbortSetupOperation;
var Code: Integer;
begin
  if Initialized then begin
    Code := NativeAbort;
    if (Code <> 8) and (Code <> Ready) then
      SuppressibleMsgBox('La operación está incompleta. Conserva los archivos de recuperación y ejecuta de nuevo el mismo instalador o uno más reciente. No se garantiza una reversión completa tras una interrupción. Los datos financieros se conservan.', mbError, MB_OK, IDOK);
  end;
  Initialized := False;
  Active := False;
end;

function InitializeContext: Integer;
begin
  Result := NativeInitialize(ExpandConstant('{tmp}\.autofinance-files'), ExpandConstant('{tmp}\myautofinance.exe'));
  Initialized := True;
  if Result = Ready then begin
    FixedDestination := Info(0);
    Support := Info(1);
    PriorVersion := Info(2);
    OperationName := Info(3);
  end;
end;

procedure InitializeWizard;
var Code: Integer;
begin
  ExtractTemporaryFile('myautofinance.exe');
  ExtractTemporaryFile('.autofinance-files');
  Code := InitializeContext;
  if Code <> Ready then RaiseException(FailureText(Code));
  if CompareText(RemoveBackslashUnlessRoot(WizardDirValue), FixedDestination) <> 0 then
    RaiseException('El destino debe ser ' + FixedDestination + '. No se admite /DIR para cambiar la identidad de instalación.');
  WizardForm.Color := $F1F5F6;
  WizardForm.Font.Name := 'Segoe UI';
  WizardForm.Font.Color := $322E20;
  WizardForm.WelcomeLabel1.Font.Color := $5F6414;
  WizardForm.FinishedHeadingLabel.Font.Color := $5F6414;
  if OperationName = 'update' then
    WizardForm.WelcomeLabel1.Caption := 'Actualizar Autofinance ' + PriorVersion + ' a {#ApplicationVersion}';
  if OperationName = 'repair' then
    WizardForm.WelcomeLabel1.Caption := 'Reparar Autofinance {#ApplicationVersion}';
  SourcePage := CreateInputFilePage(wpSelectTasks, 'Conexión local de Drive (opcional)',
    'Selecciona un único EXE de origen o continúa sin transferir',
    'No se buscan sesiones automáticamente. Sin selección y autorización, el origen se conserva. La copia de binarios no conecta Drive ni sube o descarga datos.');
  SourcePage.Add('EXE exacto de la ejecución anterior:', 'Autofinance|myautofinance.exe', '.exe');
  ConsentPage := CreateCustomPage(SourcePage.ID, '¿Transferir la conexión local de Drive?',
    'Comprueba el origen y el destino antes de autorizar');
  ConsentIntro := TNewStaticText.Create(WizardForm);
  ConsentIntro.Parent := ConsentPage.Surface;
  ConsentIntro.Width := ConsentPage.SurfaceWidth;
  ConsentIntro.Height := ScaleY(68);
  ConsentIntro.AutoSize := False;
  ConsentIntro.WordWrap := True;
  ConsentIntro.Caption := 'El destino tendrá un identificador propio. Al completar el traspaso, se retirará exclusivamente la sesión local del origen elegido, sin revocación remota.';
  SourceDetails := TNewMemo.Create(WizardForm);
  SourceDetails.Parent := ConsentPage.Surface;
  SourceDetails.Left := 0;
  SourceDetails.Top := ScaleY(76);
  SourceDetails.Width := ConsentPage.SurfaceWidth;
  SourceDetails.Height := ConsentPage.SurfaceHeight - SourceDetails.Top - ScaleY(64);
  SourceDetails.ReadOnly := True;
  SourceDetails.ScrollBars := ssVertical;
  SourceDetails.WordWrap := True;
  ConsentCheck := TNewCheckBox.Create(WizardForm);
  ConsentCheck.Parent := ConsentPage.Surface;
  ConsentCheck.Top := ConsentPage.SurfaceHeight - ScaleY(56);
  ConsentCheck.Width := ConsentPage.SurfaceWidth;
  ConsentCheck.Height := ScaleY(56);
  ConsentCheck.Caption := 'Autorizo el traspaso local entre estas rutas.';
  ConsentCheck.Checked := False;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := ((PageID = SourcePage.ID) and (OperationName <> 'install')) or
    ((PageID = ConsentPage.ID) and ((OperationName <> 'install') or (SourcePage.Values[0] = '')));
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var Buffer: String; Code: Integer;
begin
  Result := True;
  if CurPageID = SourcePage.ID then begin
    ConsentCheck.Checked := False;
    VerifiedSource := '';
    if SourcePage.Values[0] <> '' then begin
      SetLength(Buffer, 32768);
      Code := NativeSource(SourcePage.Values[0], Buffer, 32768);
      if Code <> Ready then begin
        SuppressibleMsgBox('Origen no verificable o sesión en conflicto. Selecciona un único myautofinance.exe válido o deja el campo vacío para continuar sin transferir. ' + FailureText(Code), mbError, MB_OK, IDOK);
        Result := False;
      end else begin
        VerifiedSource := SourcePage.Values[0];
        SourceDetails.Text := 'Origen: ' + VerifiedSource + #13#10 + Copy(Buffer, 1, Pos(#0, Buffer) - 1) + #13#10#13#10 +
          'Destino: ' + FixedDestination + '\myautofinance.exe' + #13#10#13#10 +
          'Las sesiones de otros directorios permanecen independientes. Sin marcar la casilla se conserva el origen.';
      end;
    end;
  end;
end;

function BackButtonClick(CurPageID: Integer): Boolean;
begin
  ConsentCheck.Checked := False;
  Result := True;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var Action, Transfer: String;
begin
  Action := 'Instalar';
  if OperationName = 'update' then Action := 'Actualizar ' + PriorVersion + ' a';
  if OperationName = 'repair' then Action := 'Reparar (misma versión)';
  Transfer := 'Sin transferencia de sesión. El origen permanece intacto.';
  if ConsentCheck.Checked and (VerifiedSource <> '') then Transfer := 'Transferencia local autorizada desde: ' + VerifiedSource;
  Result := Action + ' Autofinance {#ApplicationVersion}' + NewLine + NewLine +
    'Aplicación: ' + FixedDestination + NewLine + 'Datos y copias: ' + Support + NewLine + NewLine +
    'Se conservan datos, copias, diarios y estado Drive. Actualizar o reparar conserva la sesión y el GUID propios. La reparación no restaura la base ni baja su esquema.' + NewLine + NewLine +
    Transfer + NewLine + NewLine + MemoTasksInfo + NewLine +
    'Acceso en Inicio de este usuario. Sin inicio automático. Abrir al terminar será opcional y no ejecuta una transferencia Drive.';
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Code, Choice: Integer; Source: String;
begin
  Result := '';
  NeedsRestart := False;
  Source := '';
  if ConsentCheck.Checked and (VerifiedSource <> '') then Source := VerifiedSource;
  repeat
    Code := InitializeContext;
    if Code = Ready then Code := NativeBegin(Source);
    if Code = Ready then begin Active := True; Exit; end;
    AbortSetupOperation;
    Choice := IDCANCEL;
    if not WizardSilent then Choice := SuppressibleMsgBox(FailureText(Code), mbError, MB_RETRYCANCEL, IDCANCEL);
  until Choice <> IDRETRY;
  Result := FailureText(Code);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Code: Integer;
begin
  if CurStep = ssInstall then begin
    Code := NativeStage;
    if Code <> Ready then begin AbortSetupOperation; RaiseException(FailureText(Code)); end;
  end;
  if CurStep = ssPostInstall then begin
    Code := NativeCommit;
    InstalledOK := Code = Ready;
    if InstalledOK then Active := False
    else SuppressibleMsgBox('Operación incompleta. ' + FailureText(Code) + #13#10 +
      'No abras Autofinance hasta completar la reparación. Las migraciones pertenecen al store de la aplicación; este instalador no ejecuta SQL ni restaura esquemas.', mbError, MB_OK, IDOK);
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then begin
    if InstalledOK then WizardForm.FinishedLabel.Caption :=
      'Autofinance {#ApplicationVersion} está instalado en ' + FixedDestination + '. Datos, copias, diarios y estado Drive se conservan. Puedes abrir la aplicación desde Inicio. Abrir ahora es opcional.'
    else begin
      WizardForm.FinishedHeadingLabel.Caption := 'Operación incompleta';
      WizardForm.FinishedLabel.Caption := 'Reintenta con el mismo instalador o uno más reciente antes de abrir la aplicación. No borres datos, recibos ni marcadores. Consulta la guía de instalación y recuperación de la entrega.';
    end;
  end;
end;

function CanLaunch: Boolean;
begin
  Result := InstalledOK and not Active and not FileExists(ExpandConstant('{app}\.autofinance-pending'));
end;

function GetCustomSetupExitCode: Integer;
begin
  if InstalledOK then Result := 0 else Result := 12;
end;

procedure DeinitializeSetup;
begin
  if Initialized then begin
    if not InstalledOK then AbortSetupOperation else NativeAbort;
  end;
end;

function InitializeUninstall: Boolean;
var Code, Choice: Integer;
begin
  Result := False;
  if not SafeCommandLine then Exit;
  if UninstallSilent and not HasSwitch('/NORESTART') then begin
    SuppressibleMsgBox('La desinstalación silenciosa requiere /NORESTART.', mbError, MB_OK, IDOK);
    Exit;
  end;
  if not CopyFile(ExpandConstant('{app}\installer\autofinance_setup_bridge.dll'), ExpandConstant('{tmp}\autofinance_setup_bridge.dll'), False) then begin
    SuppressibleMsgBox('No se puede preparar la desinstalación. Cierra Autofinance normalmente y comprueba permisos y espacio. Si falta un componente, repara con el mismo instalador o uno más reciente y vuelve a desinstalar. Los datos y copias se conservan.', mbError, MB_OK, IDOK);
    Exit;
  end;
  repeat
    Code := UninstallBegin(ExpandConstant('{app}'));
    if Code = Ready then begin Active := True; Result := True; Exit; end;
    Choice := IDCANCEL;
    if not UninstallSilent then Choice := SuppressibleMsgBox(FailureText(Code), mbError, MB_RETRYCANCEL, IDCANCEL);
  until Choice <> IDRETRY;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var Code: Integer;
begin
  if CurUninstallStep = usUninstall then begin
    CleanupStarted := True;
    Code := UninstallClean;
    if Code <> Cleared then RaiseException('No se ha completado la desconexión local. Conserva el instalador y reintenta. ' + FailureText(Code));
  end;
  if CurUninstallStep = usPostUninstall then begin
    Code := UninstallFinish;
    Active := False;
    if Code <> Ready then RaiseException('La desconexión local ya se ha realizado, pero la desinstalación está incompleta. Reintenta después de liberar los archivos. Los datos y copias se conservan.');
  end;
end;

procedure DeinitializeUninstall;
var Code: Integer;
begin
  if Active then begin
    Code := UninstallAbort;
    if CleanupStarted then SuppressibleMsgBox('Desinstalación incompleta; la sesión puede haberse desconectado total o parcialmente. Reintenta para verificar la limpieza propia. Los datos y copias se conservan.', mbError, MB_OK, IDOK);
  end;
end;
