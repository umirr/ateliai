#define AppVersion "0.8.3"
#ifndef AppIdentity
  #define AppIdentity "{{2C5B407D-6E1A-4F84-A36F-EE1843A608C9}"
#endif
#ifndef BundleDir
  #define BundleDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={#AppIdentity}
AppName=Ateliai
AppVersion={#AppVersion}
AppPublisher=Ateliai
DefaultDirName={localappdata}\Programs\Storyloom
DefaultGroupName=Ateliai
UsePreviousGroup=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir=..\..\windows
OutputBaseFilename=Ateliai-Setup-{#AppVersion}-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\storyloom.exe
SetupIconFile=..\windows\runner\resources\app_icon.ico
CloseApplications=yes
RestartApplications=no
DisableProgramGroupPage=yes
SetupLogging=yes
VersionInfoDescription=Ateliai Windows Installer

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: files; Name: "{autodesktop}\Storyloom.lnk"
Type: files; Name: "{userprograms}\Storyloom\Storyloom.lnk"

[Icons]
#ifdef QADataDir
Name: "{group}\Ateliai QA"; Filename: "{app}\storyloom.exe"; Parameters: """--data-dir={#QADataDir}"""; WorkingDir: "{app}"
#else
Name: "{group}\Ateliai"; Filename: "{app}\storyloom.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Ateliai"; Filename: "{app}\storyloom.exe"; WorkingDir: "{app}"; Tasks: desktopicon
#endif

[Run]
Filename: "{app}\storyloom.exe"; Description: "{cm:LaunchProgram,Ateliai}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
