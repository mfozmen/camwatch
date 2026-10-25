; The Windows setup (Inno Setup 6). It installs for the signed-in user only
; (%LOCALAPPDATA%\Programs\camwatch), never needing admin rights; /ALLUSERS on
; the command line still installs for everyone. The release workflow builds it with
;   iscc /DAppVersion=1.2.3 /DSourceDir=<flutter Release folder> /O<out> /F<name> camwatch.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
; Never change the AppId: Windows recognises installed versions by it.
AppId={{9AB18EDE-8B6B-47A9-8E59-7DB4959CA69F}
AppName=camwatch
AppVersion={#AppVersion}
AppPublisher=mfozmen
AppPublisherURL=https://github.com/mfozmen/camwatch
DefaultDirName={autopf}\camwatch
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\camwatch.exe
SetupIconFile=..\runner\resources\app_icon.ico
; Installed apps shows the version in its own column: the name is just the name.
UninstallDisplayName=camwatch
CloseApplications=force
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputBaseFilename=camwatch-setup

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "tr"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\camwatch"; Filename: "{app}\camwatch.exe"
Name: "{autodesktop}\camwatch"; Filename: "{app}\camwatch.exe"; Tasks: desktopicon

[Run]
; As the signed-in user, never as an elevated setup.
Filename: "{app}\camwatch.exe"; Description: "{cm:LaunchProgram,camwatch}"; Flags: nowait postinstall skipifsilent runasoriginaluser
