# Cómo publicar un APK sin borrar la familia en el servidor
#
# Uso (PowerShell), desde llegue-mobile, con el APK ya buildeado:
#   .\scripts\publish-apk-release.ps1 -Version "1.0.0+6"
#
# Esto sube el APK a GitHub Releases. La API solo redirige a ese link
# y NO se redeploya → la base SQLite en Render no se toca.

param(
  [Parameter(Mandatory = $true)]
  [string]$Version,
  [string]$ApkPath = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $ApkPath) {
  $ApkPath = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
}
if (-not (Test-Path $ApkPath)) {
  throw "No está el APK: $ApkPath. Corré flutter build apk --release primero."
}

$tag = "v$($Version -replace '\+','-')"
$assetName = "Llegue.apk"
$staged = Join-Path $env:TEMP $assetName
Copy-Item $ApkPath $staged -Force

Write-Host "Publicando $tag ($ApkPath) ..."
gh release create $tag $staged `
  --repo enzomantay-del/llegue-mobile `
  --title "Llegué $Version" `
  --notes "Instalá ENCIMA de la versión anterior (no desinstales). La familia en el servidor no se borra con esta publicación." `
  --latest

Write-Host "Listo. Descarga: https://github.com/enzomantay-del/llegue-mobile/releases/latest/download/Llegue.apk"
Write-Host "O desde: https://llegue-api.onrender.com/download/llegue.apk"
