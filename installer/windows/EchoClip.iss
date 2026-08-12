#ifndef AppVersion
  #define AppVersion "0.4.0"
#endif
#ifndef AppBuildNumber
  #define AppBuildNumber "0"
#endif
#ifndef SourceDir
  #error SourceDir must point at the Flutter Windows Release directory.
#endif
#ifndef OutputDir
  #error OutputDir must point at the package output directory.
#endif
#ifndef RepoRoot
  #error RepoRoot must point at the EchoClip repository root.
#endif
#if !FileExists(SourceDir + "\echoclip.exe")
  #error SourceDir does not contain echoclip.exe.
#endif
#if !FileExists(SourceDir + "\flutter_windows.dll")
  #error SourceDir does not contain flutter_windows.dll.
#endif
#if !FileExists(SourceDir + "\echoclip_windows_ffi.dll")
  #error SourceDir does not contain echoclip_windows_ffi.dll.
#endif
#if !FileExists(SourceDir + "\ffmpeg.exe")
  #error SourceDir does not contain the bundled Windows x64 ffmpeg.exe.
#endif
#if !FileExists(SourceDir + "\licenses\FFmpeg-Windows-NOTICE.txt")
  #error SourceDir does not contain the FFmpeg distribution notice.
#endif
#if !DirExists(SourceDir + "\data")
  #error SourceDir does not contain the Flutter data directory.
#endif

[Setup]
AppId={{D723B11E-09C8-438B-AB36-8A3A31D50395}
AppName=EchoClip
AppVersion={#AppVersion}
VersionInfoVersion={#AppVersion}.{#AppBuildNumber}
VersionInfoProductVersion={#AppVersion}.{#AppBuildNumber}
AppPublisher=EchoClip
DefaultDirName={localappdata}\Programs\EchoClip
DefaultGroupName=EchoClip
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
MinVersion=10.0.15063
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=EchoClip-{#AppVersion}-x64-Setup
SetupIconFile={#RepoRoot}\apps\echoclip\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\echoclip.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
DirExistsWarning=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\EchoClip"; Filename: "{app}\echoclip.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\EchoClip"; Filename: "{app}\echoclip.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\echoclip.exe"; Description: "{cm:LaunchProgram,EchoClip}"; Flags: nowait postinstall skipifsilent
