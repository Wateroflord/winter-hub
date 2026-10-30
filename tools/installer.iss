; Установщик Winter Hub для Windows (Inno Setup 6). Ставится без прав администратора в профиль пользователя.
#define BuildNo GetEnv("BUILD_NO")
#if BuildNo == ""
  #define BuildNo "0"
#endif

[Setup]
AppId={{6E2F4A80-1C3B-4D57-9E68-0A7B2C4D5E91}
AppName=Winter Hub
AppVersion=1.0.{#BuildNo}
AppPublisher=Winter Hub
DefaultDirName={localappdata}\Programs\Winter Hub
DefaultGroupName=Winter Hub
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Winter-Hub-Setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\winter_hub.exe
CloseApplications=force
RestartApplications=no
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Winter Hub"; Filename: "{app}\winter_hub.exe"
Name: "{group}\{cm:UninstallProgram,Winter Hub}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Winter Hub"; Filename: "{app}\winter_hub.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\winter_hub.exe"; Description: "{cm:LaunchProgram,Winter Hub}"; Flags: nowait postinstall skipifsilent
; После тихого автообновления — снова запустить приложение.
Filename: "{app}\winter_hub.exe"; Flags: nowait; Check: WizardSilent
