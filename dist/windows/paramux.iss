#define AppName "paramux"
#define AppId "io.github.soldforaloss.paramux"
#define AppUserModelId "io.github.soldforaloss.paramux"
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0-dev"
#endif
#ifndef PackageArch
  #define PackageArch "x64"
#endif
#ifndef StageDir
  #error StageDir must be defined on the ISCC command line.
#endif
#ifndef OutputDir
  #error OutputDir must be defined on the ISCC command line.
#endif
#ifndef SourceDir
  #define SourceDir "."
#endif

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#MyAppVersion}
AppPublisher=Aman Thanvi
AppPublisherURL=https://github.com/soldforaloss/paramux
AppSupportURL=https://github.com/soldforaloss/paramux/issues
AppUpdatesURL=https://github.com/soldforaloss/paramux/releases
DefaultDirName={autopf}\paramux
DefaultGroupName=paramux
DisableProgramGroupPage=yes
LicenseFile={#StageDir}\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=paramux-{#MyAppVersion}-windows-{#PackageArch}-setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
#if PackageArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
ChangesAssociations=no
CloseApplications=yes
RestartApplications=yes
UninstallDisplayIcon={app}\paramux.exe
SetupIconFile={#SourceDir}\dist\windows\paramux.ico
VersionInfoVersion={#MyAppVersion}
VersionInfoTextVersion={#MyAppVersion}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoProductTextVersion={#MyAppVersion}
VersionInfoCompany=Aman Thanvi
VersionInfoDescription=paramux Setup
VersionInfoProductName=paramux
VersionInfoOriginalFileName=paramux-{#MyAppVersion}-windows-{#PackageArch}-setup.exe

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
Name: "contextmenu"; Description: "Add ""Open in Paramux"" to the Explorer right-click menu for folders"

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; Explorer "Open in Paramux" verbs (per-user; mirrors install-paramux.ps1 and
; src\apprt\win32_explorer_menu.zig). "%V\." instead of "%V": a root folder's
; trailing backslash would escape the closing quote otherwise.
[Registry]
Root: HKCU; Subkey: "Software\Classes\Directory\shell\Paramux"; ValueType: string; ValueData: "Open in Paramux"; Flags: uninsdeletekey; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\Directory\shell\Paramux"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\paramux.exe"",0"; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\Directory\shell\Paramux\command"; ValueType: string; ValueData: """{app}\paramux.exe"" --working-directory=""%V\."""; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\Paramux"; ValueType: string; ValueData: "Open in Paramux"; Flags: uninsdeletekey; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\Paramux"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\paramux.exe"",0"; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\Paramux\command"; ValueType: string; ValueData: """{app}\paramux.exe"" --working-directory=""%V\."""; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\Drive\shell\Paramux"; ValueType: string; ValueData: "Open in Paramux"; Flags: uninsdeletekey; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\Drive\shell\Paramux"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\paramux.exe"",0"; Tasks: contextmenu
Root: HKCU; Subkey: "Software\Classes\Drive\shell\Paramux\command"; ValueType: string; ValueData: """{app}\paramux.exe"" --working-directory=""%V\."""; Tasks: contextmenu

[Icons]
Name: "{group}\paramux"; Filename: "{app}\paramux.exe"; AppUserModelID: "{#AppUserModelId}"
Name: "{group}\Uninstall paramux"; Filename: "{uninstallexe}"
Name: "{autodesktop}\paramux"; Filename: "{app}\paramux.exe"; Tasks: desktopicon; AppUserModelID: "{#AppUserModelId}"

[Run]
Filename: "{app}\paramux.exe"; Description: "Launch paramux"; Flags: nowait postinstall skipifsilent
