# Retire Ilot (exe installe + lancement au demarrage). Le code source reste ici.
Get-Process ilot -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item (Join-Path ([Environment]::GetFolderPath("Startup")) "Ilot.lnk") -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:LOCALAPPDATA "Programs\Ilot") -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Ilot desinstalle"
