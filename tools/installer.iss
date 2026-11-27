; Установщик Winter Sprites для Windows (Inno Setup 6). Ставится без прав администратора в профиль пользователя.
#define BuildNo GetEnv("BUILD_NO")
#if BuildNo == ""
  #define BuildNo "0"
#endif

[Setup]
AppId={{7C505BCA-4CD0-4B27-8A09-411C67958FE1}
AppName=Winter Sprites
AppVersion=1.0.{#BuildNo}
AppPublisher=Winter Hub
DefaultDirName={localappdata}\Programs\Winter Sprites
DefaultGroupName=Winter Sprites
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Winter-Sprites-Setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\winter_sprites.exe
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
Name: "{group}\Winter Sprites"; Filename: "{app}\winter_sprites.exe"
Name: "{group}\{cm:UninstallProgram,Winter Sprites}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Winter Sprites"; Filename: "{app}\winter_sprites.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\winter_sprites.exe"; Description: "{cm:LaunchProgram,Winter Sprites}"; Flags: nowait postinstall skipifsilent
; После тихого автообновления — снова запустить приложение.
Filename: "{app}\winter_sprites.exe"; Flags: nowait; Check: WizardSilent
