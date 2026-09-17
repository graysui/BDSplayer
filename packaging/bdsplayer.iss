; BDSplayer Inno Setup Script
#define MyAppName "BDSplayer"
#define MyAppEnglishName "BDSplayer"
#define MyAppTitle "BDSplayer - 百度网盘视频播放器"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.3"
#endif
#define MyAppExeName "BDSplayer.exe"

[Setup]
AppId={{E88425F8-13E5-46D9-B5B3-7892C80DF101}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} v{#MyAppVersion}
AppPublisher={#MyAppEnglishName}
VersionInfoVersion={#MyAppVersion}
DefaultDirName={localappdata}\Programs\{#MyAppEnglishName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename={#MyAppEnglishName}-v{#MyAppVersion}-x64-Setup
OutputDir=dist
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupIconFile=app.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=yes
CloseApplicationsFilter={#MyAppExeName},bds-server.exe,bdpan.exe
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "packaging\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Payload files - completely clean, zero tokens or auth states
Source: "dist\payload\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "dist\payload\disclaimer_accepted.json"; DestDir: "{userappdata}\..\.config\bdpan"; Flags: ignoreversion uninsneveruninstall
Source: "dist\payload\disclaimer_accepted.json"; DestDir: "{userappdata}\..\.config\BDSplayer"; Flags: ignoreversion uninsneveruninstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\app.ico"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\app.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{%USERPROFILE}\.config\BDSplayer"
