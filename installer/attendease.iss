; Inno Setup script for AttendEase
; Build the app first:  flutter build windows --release
; Then compile this script with Inno Setup 6 (ISCC.exe) to produce the installer.

#define MyAppName "AttendEase"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Intishar-Ul Islam"
#define MyAppURL "https://github.com/Nahianether"
#define MyAppExeName "attend_ease.exe"

; Folder containing the release build output (attend_ease.exe + DLLs + data\)
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
; A unique AppId keeps upgrades/uninstall tied to the same product across versions.
AppId={{8F3C1A6E-2D4B-4E91-9B7A-AE51C0D2F7A1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; Install per-user by default so no admin rights are required; allow elevation if chosen.
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=Output
OutputBaseFilename=AttendEase-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole release folder: exe, sibling DLLs, and the data\ tree (incl. bundled fonts).
Source: "{#BuildDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
