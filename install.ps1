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

# raccourci dans le dossier Demarrage
$startup = [Environment]::GetFolderPath("Startup")
$sh = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $startup "Ilot.lnk"))
$sh.TargetPath = Join-Path $dest "ilot.exe"
$sh.WorkingDirectory = $dest
$sh.Save()

Start-Process (Join-Path $dest "ilot.exe")
Write-Host "Ilot installe et lance depuis $dest"
