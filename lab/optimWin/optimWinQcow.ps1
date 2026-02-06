# =================================================
# Windows 10 Pro Optimization Script (ISO version)
# Exécutable depuis un CD-ROM (lecture seule)
# =================================================

# ==========================================
# 1) Chargement de la configuration externe       
# ==========================================
$ConfigFile = Join-Path $PSScriptRoot "optimize.config.ps1"
if (Test-Path $ConfigFile) {
    . $ConfigFile
}

# ==================
# 2) Bootstrap code
# ==================
# --- Bootstrap : autodétection du lecteur CD et exécution du vrai script ---
# Nom du script réel (injecté depuis Linux via optimize.config.ps1)
# Exemple attendu :
#   $OptimizeScriptName = 'optimWinQcow.ps1'
# Détection du lecteur CD-ROM
$cdrom = Get-WmiObject Win32_LogicalDisk |
         Where-Object { $_.DriveType -eq 5 } |
         Select-Object -ExpandProperty DeviceID
Write-Host "Lecteur CD-ROM détecté : $cdrom"
# Construction du chemin complet
$scriptPath = Join-Path $cdrom $OptimizeScriptName
Write-Host "Exécution du script réel : $scriptPath"
# Si on est en train d'exécuter le bootstrap depuis l'ISO,
# alors on lance le vrai script et on s'arrête là.
if ($MyInvocation.MyCommand.Path -ne $scriptPath) {
    & $scriptPath
    exit
}
# ====================
# End of bootstrap code
# ====================

Write-Host "Optimisation Windows 10 Pro pour VM QEMU..." -ForegroundColor Cyan

# --- Désactivation des services lourds ---
$servicesToDisable = @(
    "SysMain",
    "WSearch",
    "DiagTrack",
    "dmwappushservice",
    "RetailDemo",
    "MapsBroker",
    "XblAuthManager",
    "XblGameSave",
    "XboxNetApiSvc",
    "XboxGipSvc",
    "PrintSpooler"
)

foreach ($svc in $servicesToDisable) {
    Write-Host "Désactivation du service : $svc"
    Stop-Service $svc -ErrorAction SilentlyContinue
    Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
}

# --- Services à mettre en manuel ---
$servicesToManual = @(
    "wuauserv",   # Windows Update
    "WinDefend"   # Windows Defender
)

foreach ($svc in $servicesToManual) {
    Write-Host "Mise en manuel : $svc"
    Set-Service $svc -StartupType Manual -ErrorAction SilentlyContinue
}

# --- Suppression des AppX inutiles ---
$appxList = @(
    "*xbox*",
    "*zune*",
    "*bing*",
    "*skype*",
    "*onenote*",
    "*officehub*",
    "*solitaire*",
    "*people*",
    "*maps*",
    "*3d*"
)

foreach ($app in $appxList) {
    Write-Host "Suppression AppX : $app"
    Get-AppxPackage $app | Remove-AppxPackage -ErrorAction SilentlyContinue
}

Write-Host "Suppression OneDrive..."
taskkill /f /im OneDrive.exe 2>$null
$od = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
if (Test-Path $od) {
    Start-Process $od "/uninstall" -Wait
}

# --- Désactivation hibernation ---
Write-Host "Désactivation de l'hibernation..."
powercfg /h off

# --- Désactivation indexation disque ---
Write-Host "Désactivation de l'indexation du disque C:..."
$vol = Get-WmiObject -Class Win32_Volume -Filter "DriveLetter='C:'"
$vol.IndexingEnabled = $false
$vol.Put() | Out-Null

# --- Nettoyage WinSxS ---
Write-Host "Nettoyage WinSxS..."
Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase

# --- Désactivation animations Windows ---
Write-Host "Désactivation des animations..."
Set-ItemProperty "HKCU:\Control Panel\Desktop" "UserPreferencesMask" (
    [byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)
)

# =================================================
#           PRÉPARATION AU SHRINK (étape cruciale)
# =================================================
Write-Host ""
Write-Host "Préparation au shrink de la partition C:..." -ForegroundColor Yellow

# --- Désactivation restauration système ---
Write-Host "Désactivation de la restauration système..."
Disable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue

# --- Désactivation du pagefile ---
Write-Host "Désactivation du fichier d'échange (pagefile)..."
$mm = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
Set-ItemProperty $mm PagingFiles ""
Set-ItemProperty $mm ExistingPageFiles ""
Set-ItemProperty $mm TempPageFile 0
Write-Host "Pagefile désactivé. Il sera supprimé au prochain arrêt complet."

# --- Nettoyage fichiers temporaires ---
Write-Host "Nettoyage des fichiers temporaires..."
Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/verylowdisk" -Wait

Write-Host "Création du script post-redémarrage..."
$postScript = @'
Write-Host "Défragmentation de C:..."
defrag C: /U /V
Write-Host "Extinction après défragmentation..."
Stop-Computer -Force
'@

Set-Content -Path "C:\post-shrink.ps1" -Value $postScript -Encoding UTF8

Write-Host "Configuration de l'exécution automatique..."
Set-ItemProperty `
  -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
  -Name "PostShrink" `
  -Value "powershell.exe -ExecutionPolicy Bypass -File C:\post-shrink.ps1"

Read-Host "Appuie sur Entrée pour éteindre Windows..."
Stop-Computer -Force
