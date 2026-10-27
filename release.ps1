# Publie une version depuis le poste (memes etapes que .github/workflows/release.yml,
# plus la signature de l'archive, exigee par src/update.rs) :
#   powershell -ExecutionPolicy Bypass -File release.ps1            compile, emballe, signe, publie
#   powershell -ExecutionPolicy Bypass -File release.ps1 -NoPublish  tout sauf la publication
# Avant : version dans Cargo.toml, section `## <version> — <date>` dans CHANGELOG.md,
# commit pousse sur GitHub. Cle privee : %USERPROFILE%\.ilot\release.key (hors du depot).
param([switch]$NoPublish, [string]$Key = "$env:USERPROFILE\.ilot\release.key")
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"

$v = (Select-String -Path Cargo.toml -Pattern '^version = "(.+)"').Matches[0].Groups[1].Value
$zip = "ilot-$v-win64.zip"
Write-Host "Version $v"

# --- verifications avant de compiler
if (-not (Test-Path $Key)) { throw "Cle de signature introuvable : $Key" }
$head = Get-Content CHANGELOG.md -Encoding utf8 | Where-Object { $_ -match "^## v?$([regex]::Escape($v))\b" } | Select-Object -First 1
if (-not $head) { throw "Pas de section ## $v dans CHANGELOG.md" }
if ($head -notmatch '\d{4}-\d{2}-\d{2}\s*$') { throw "Section ## $v sans date dans CHANGELOG.md : $head" }
if (git status --porcelain) { throw "Des modifications ne sont pas commitees" }
if (git tag -l "v$v") { throw "Le tag v$v existe deja" }
$sha = git rev-parse HEAD
if (-not $NoPublish) {
    git fetch --quiet origin
    if (-not (git branch -r --contains $sha)) { throw "Le commit $sha n'est pas pousse sur GitHub" }
}

# --- la cle correspond a celle qu'embarque l'ilot
$pub = (cargo run --quiet --release --example sign -- pub $Key)
if ($LASTEXITCODE -ne 0) { throw "examples/sign.rs a echoue" }
if (-not (Select-String -Path src\update.rs -SimpleMatch "const SIGN_KEY: &str = `"$pub`"" -Quiet)) {
    throw "La cle $Key ne correspond pas a SIGN_KEY (src/update.rs)"
}

# --- compilation (le message 'vswhere.exe' de vcvars64 est sans effet)
cmd /c "qt\build.cmd"
if ($LASTEXITCODE -ne 0) { throw "Echec de la compilation" }

# --- archive : memes fichiers que install.ps1, dans un dossier Ilot\
if (Test-Path dist) { Remove-Item dist -Recurse -Force }
if (Test-Path $zip) { Remove-Item $zip -Force }
robocopy "qt\build" "dist\Ilot" /E /XD CMakeFiles .rcc .qt ilot_autogen Ilot /XF *.obj *.ninja* *.cmake CMakeCache.txt *.lib *.exp *.pdb *.ilk /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy $LASTEXITCODE" }
if (-not (Test-Path "dist\Ilot\ilot.exe")) { throw "ilot.exe absent de dist\Ilot" }
Compress-Archive -Path "dist\Ilot" -DestinationPath $zip

# --- signature : ilot-<version>-win64.zip.sig
cargo run --quiet --release --example sign -- sign $Key $zip $v | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Echec de la signature" }

# --- notes : la section `## <version>` de CHANGELOG.md
$notes = @(); $in = $false
foreach ($l in Get-Content CHANGELOG.md -Encoding utf8) {
    if ($l -match '^## ') { if ($in) { break }; $in = $l -match "^## v?$([regex]::Escape($v))\b"; continue }
    if ($in) { $notes += $l }
}
# sans BOM (Out-File en met un sous PowerShell 5, et il finirait dans les notes)
[IO.File]::WriteAllText("$PWD\notes.md", ($notes -join "`n").Trim(), (New-Object Text.UTF8Encoding $false))

if ($NoPublish) {
    Write-Host "Pret (non publie) : $zip, $zip.sig, notes.md"
    exit 0
}

# --- publication (cree aussi le tag v<version> sur ce commit)
$title = "$([char]0x00CE)lot $v"
gh release create "v$v" $zip "$zip.sig" --title $title --notes-file notes.md --target $sha
if ($LASTEXITCODE -ne 0) { throw "gh release create a echoue" }
git fetch --quiet --tags origin
Write-Host "Version v$v publiee"
