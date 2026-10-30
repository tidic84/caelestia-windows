# Compile Ilot et l'installe dans %LOCALAPPDATA%\Programs\Ilot (+ lancement au demarrage).
# Relancer apres chaque modification :  powershell -ExecutionPolicy Bypass -File install.ps1
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"

# coeur Rust puis interface Qt (qt\build.cmd)
cmd /c "qt\build.cmd"
if ($LASTEXITCODE -ne 0) { throw "Echec de la compilation" }

$dest = Join-Path $env:LOCALAPPDATA "Programs\Ilot"
New-Item -ItemType Directory -Force $dest | Out-Null

# arrete l'instance en cours pour pouvoir remplacer les fichiers
Get-Process ilot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
# l'executable, le coeur Rust et les DLL de Qt (sans les fichiers de compilation)
robocopy "qt\build" $dest /MIR /XD CMakeFiles .rcc .qt ilot_autogen Ilot /XF *.obj *.ninja* *.cmake CMakeCache.txt *.lib *.exp *.pdb *.ilk /NFL /NDL /NJH /NJS | Out-Null

# lancement a l'ouverture de session par une tache planifiee (comme le reglage,
# src/settings.rs) : le dossier Demarrage et la cle Run passent par la file de
# l'Explorateur, qui lancait l'ilot 2 a 3 min apres l'ouverture de session
$exe = Join-Path $dest "ilot.exe"
$user = "$env:USERDOMAIN\$env:USERNAME"
Remove-Item (Join-Path ([Environment]::GetFolderPath("Startup")) "Ilot.lnk") -ErrorAction SilentlyContinue
Remove-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name Ilot -ErrorAction SilentlyContinue
$task = New-ScheduledTask `
    -Action (New-ScheduledTaskAction -Execute $exe -Argument "--autostart" -WorkingDirectory $dest) `
    -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $user) `
    -Principal (New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited) `
    -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -Priority 4 -MultipleInstances IgnoreNew)
Register-ScheduledTask -TaskName Ilot -InputObject $task -Force | Out-Null

Start-Process (Join-Path $dest "ilot.exe")
Write-Host "Ilot installe et lance depuis $dest"
