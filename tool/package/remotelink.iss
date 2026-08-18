; Inno Setup script for the Remote Link desktop companion.
;
; Not run directly — `tool/package/windows.ps1` builds the app first and passes
; the version in, so the installer and the binary can never disagree about which
; release this is.
;
; Inno Setup rather than MSIX: MSIX runs the app in a container with its own
; virtualised registry and file system, which breaks the two things this app
; must do — write a `Run` key the real user session reads, and open a listening
; socket other machines can reach. Those are exactly the capabilities a
; packaged app is prevented from having.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\apps\desktop\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{8F3B7A16-4B2E-4C5A-9E7D-2A1C6F0B9D34}
AppName=Remote Link
AppVersion={#AppVersion}
AppPublisher=Remote Link
DefaultDirName={autopf}\Remote Link
DefaultGroupName=Remote Link
; Per-user by default. The app needs no elevation to run, and asking for
; administrator at install time trains people to grant it to a program whose
; whole job is to accept input from the network.
PrivilegesRequiredOverridesAllowed=dialog
PrivilegesRequired=lowest
OutputDir=..\..\build\release
OutputBaseFilename=RemoteLink-{#AppVersion}-setup
SetupIconFile=..\..\apps\desktop\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\remotelink_desktop.exe
; Refuses to install over a running copy rather than leaving half-replaced
; files behind — and the app now survives its window being closed, so "I closed
; it" no longer means "it is not running".
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startup"; Description: "Start Remote Link when I sign in"; GroupDescription: "Startup"
Name: "firewall"; Description: "Allow Remote Link through Windows Firewall on private networks"; GroupDescription: "Network"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Remote Link"; Filename: "{app}\remotelink_desktop.exe"
Name: "{autodesktop}\Remote Link"; Filename: "{app}\remotelink_desktop.exe"; Tasks: startup

[Registry]
; The same `Run` key `AutoStart` writes, with the same `--minimised` flag, so
; the installer's choice and the app's own setting describe one thing rather
; than fighting each other.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; \
  ValueType: string; ValueName: "com.example.remotelinkDesktop"; \
  ValueData: """{app}\remotelink_desktop.exe"" --minimised"; \
  Flags: uninsdeletevalue; Tasks: startup

[Run]
; Created here rather than at first launch, deliberately. A firewall prompt
; appears behind the app's own window, is dismissed by reflex, and leaves a
; companion the phone cannot reach with nothing on screen explaining why.
; Private profile only: this is a home and office network product, and a rule
; covering public Wi-Fi is a rule nobody asked for.
Filename: "netsh"; \
  Parameters: "advfirewall firewall add rule name=""Remote Link"" dir=in action=allow program=""{app}\remotelink_desktop.exe"" enable=yes profile=private"; \
  Flags: runhidden; Tasks: firewall

Filename: "{app}\remotelink_desktop.exe"; \
  Description: "Start Remote Link"; \
  Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "netsh"; \
  Parameters: "advfirewall firewall delete rule name=""Remote Link"""; \
  Flags: runhidden; RunOnceId: "RemoveFirewallRule"
