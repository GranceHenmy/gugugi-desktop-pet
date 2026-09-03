#define MyAppName "咕咕叽桌面宠物"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "GranceHenmy"
#define MyAppExeName "LaunchBird.vbs"

[Setup]
AppId={{B98F50D7-4722-44CD-A490-B6D856942072}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\GugugiDesktopPet
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=咕咕叽桌面宠物-安装包-v{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#MyAppName}
CloseApplications=no

[Tasks]
Name: "startup"; Description: "登录 Windows 后自动启动（推荐）"; GroupDescription: "启动选项："; Flags: checkedonce

[Files]
Source: "..\CodexBirdPet.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LaunchBird.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\StopBird.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\prepared-v12\idle\*.png"; DestDir: "{app}\assets\prepared-v12\idle"; Flags: ignoreversion
Source: "..\assets\prepared-v12\typing\*.png"; DestDir: "{app}\assets\prepared-v12\typing"; Flags: ignoreversion
Source: "..\assets\prepared-v12\thinking\*.png"; DestDir: "{app}\assets\prepared-v12\thinking"; Flags: ignoreversion
Source: "..\assets\prepared-v12\complete\*.png"; DestDir: "{app}\assets\prepared-v12\complete"; Flags: ignoreversion
Source: "..\assets\prepared-v12\waiting\*.png"; DestDir: "{app}\assets\prepared-v12\waiting"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\{#MyAppExeName}"""; WorkingDir: "{app}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{userstartup}\咕咕叽桌面宠物"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\{#MyAppExeName}"""; WorkingDir: "{app}"; Tasks: startup

[Run]
Filename: "{sys}\wscript.exe"; Parameters: """{app}\{#MyAppExeName}"""; Description: "立即启动绿色小鸟"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\StopBird.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "StopGugugiDesktopPet"

[UninstallDelete]
Type: files; Name: "{app}\settings.json"
Type: dirifempty; Name: "{app}"
