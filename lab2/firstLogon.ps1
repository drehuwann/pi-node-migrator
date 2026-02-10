# Désactivation hibernation
powercfg -h off

# Désactivation pagefile
wmic computersystem where name="%computername%" set AutomaticManagedPagefile=False
wmic pagefileset delete

# Désactivation animations et thème moderne
Set-ItemProperty "HKCU:\Control Panel\Desktop" UserPreferencesMask ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00))
Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0
Set-Service Themes -StartupType Disabled
Stop-Service Themes -Force

# Activation SSH client
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

# Désactivation services inutiles
$services = @(
  "SysMain","WSearch","DiagTrack","dmwappushservice","RetailDemo",
  "MapsBroker","RemoteRegistry","Fax","WMPNetworkSvc","TabletInputService",
  "WerSvc","DoSvc","WaaSMedicSvc","XblAuthManager","XblGameSave",
  "XboxNetApiSvc","BluetoothUserService","BTAGService","BthAvctpSvc",
  "PhoneSvc","WbioSrvc","lfsvc","wisvc","SharedAccess","TrkWks",
  "WpcMonSvc","SEMgrSvc","MessagingService","PimIndexMaintenanceSvc",
  "WpnService","WpnUserService"
)

foreach ($s in $services) {
  Get-Service $s -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled
  Stop-Service $s -Force -ErrorAction SilentlyContinue
}

# Désactivation télémétrie
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" AllowTelemetry 0
schtasks /Change /TN "\Microsoft\Windows\Application Experience\ProgramDataUpdater" /Disable
schtasks /Change /TN "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator" /Disable

Get-AppxPackage -AllUsers *Bing* | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like "*Bing*"} | Remove-AppxProvisionedPackage -Online

Get-AppxPackage -AllUsers *Xbox* | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like "*Xbox*"} | Remove-AppxProvisionedPackage -Online

Get-AppxPackage -AllUsers *Teams* | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like "*Teams*"} | Remove-AppxProvisionedPackage -Online

Get-AppxPackage -AllUsers *Cortana* | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like "*Cortana*"} | Remove-AppxProvisionedPackage -Online

Get-AppxPackage -AllUsers Microsoft.WindowsStore | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -eq "Microsoft.WindowsStore"} | Remove-AppxProvisionedPackage -Online

Get-AppxPackage -AllUsers *WebExperience* | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like "*WebExperience*"} | Remove-AppxProvisionedPackage -Online

Get-AppxPackage -AllUsers *Paint* | Remove-AppxPackage
Get-AppxPackage -AllUsers *Photos* | Remove-AppxPackage
Get-AppxPackage -AllUsers *Zune* | Remove-AppxPackage
Get-AppxPackage -AllUsers *Media* | Remove-AppxPackage

Get-AppxPackage -AllUsers *Maps* | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like "*Maps*"} | Remove-AppxProvisionedPackage -Online

Get-AppxPackage -AllUsers *People* | Remove-AppxPackage
Get-AppxPackage -AllUsers *Messaging* | Remove-AppxPackage
Get-AppxPackage -AllUsers *CommsPhone* | Remove-AppxPackage
Get-AppxPackage -AllUsers *WindowsPhone* | Remove-AppxPackage

Get-AppxPackage -AllUsers *3D* | Remove-AppxPackage
Get-AppxPackage -AllUsers *Print3D* | Remove-AppxPackage
Get-AppxPackage -AllUsers *Sticky* | Remove-AppxPackage
Get-AppxPackage -AllUsers *Whiteboard* | Remove-AppxPackage

$keep = @(
  "Microsoft.WindowsNotepad",
  "Microsoft.PowerShell",
  "Microsoft.WindowsTerminal",
  "Microsoft.SecHealthUI"
)

Get-AppxPackage -AllUsers | Where-Object { $keep -notcontains $_.Name } | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object { $keep -notcontains $_.DisplayName } | Remove-AppxProvisionedPackage -Online

# Suppression OneDrive
taskkill /F /IM OneDrive.exe
Start-Process "C:\Windows\SysWOW64\OneDriveSetup.exe" "/uninstall" -Wait

# Désactivation indexation
Stop-Service WSearch -Force
Set-Service WSearch -StartupType Disabled

# Désactivation restauration système
Disable-ComputerRestore -Drive "C:\"

# Nettoyage fichiers temporaires
Remove-Item -Recurse -Force "C:\Windows\Temp\*" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:TEMP\*" -ErrorAction SilentlyContinue

# Nettoyage WinSxS
Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase

# Planification second script
$script = "powershell -ExecutionPolicy Bypass -File C:\SecondLogon.ps1"
schtasks /Create /TN "SecondLogon" /TR "$script" /SC ONLOGON /RL HIGHEST /F
