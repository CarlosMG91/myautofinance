; Synthetic compiler probe, /O- only: no installer output or UI implementation.
#if VER != 0x06050400
  #error Inno Setup 6.5.4 required
#endif
[Setup]
AppName=Synthetic compiler probe
AppVersion=0
DefaultDirName={tmp}\AutofinanceCompilerProbe
PrivilegesRequired=lowest
Uninstallable=no
CreateAppDir=no
OutputDir=..\..\dist-private\windows\compiler-probe
