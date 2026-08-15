; Frida Link installer
; Build: ISCC.exe frida_link_setup.iss   (Inno Setup 6)
; Requires a fresh `flutter build windows --release` first.

#define MyAppName "Frida Link"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Frida Link"
#define MyAppExeName "frida_link_v2.exe"

[Setup]
AppId=C4F9E8D1-5A2B-4C3D-9E8F-1A2B3C4D5E6F
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; Pre-filled default install path. With PrivilegesRequiredOverridesAllowed the
; user can pick per-user (no admin) or all-users (elevated), and {autopf}
; resolves to the right default (Program Files vs %LOCALAPPDATA%\Programs).
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#SourcePath}dist
OutputBaseFilename=FridaLink-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#SourcePath}..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
; Offer "install for me only" (no admin) vs "for all users" (elevated).
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Path to the freshly built Flutter release.
SourceDir=../build/windows/x64/runner/Release

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"
Name: "contextmenu"; Description: "Add 'Open with Frida Link' to the Explorer context menu for .ts/.js scripts"; GroupDescription: "Additional icons:"; Flags: checkedonce

[Files]
Source: "frida_link_v2.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

; "Open with Frida Link" in Windows Explorer for .ts / .js scripts. HKA maps
; to HKLM for all-users installs and HKCU for per-user installs.
[Registry]
Root: HKA; Subkey: "Software\Classes\.ts"; ValueType: string; ValueName: ""; ValueData: "FridaLinkScript"; Flags: uninsdeletevalue; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\.js"; ValueType: string; ValueName: ""; ValueData: "FridaLinkScript"; Flags: uninsdeletevalue; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\FridaLinkScript\shell\open"; ValueType: string; ValueName: ""; ValueData: "Open with Frida Link"; Flags: uninsdeletekey; Tasks: contextmenu
Root: HKA; Subkey: "Software\Classes\FridaLinkScript\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey; Tasks: contextmenu

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
{ Kill any running instance before files are replaced, otherwise the exe is locked. }
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssInstall then
    Exec('taskkill', '/F /IM {#MyAppExeName}', '', 0, ewWaitUntilTerminated, ResultCode);
end;