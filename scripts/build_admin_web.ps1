$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$FvmConfig = Get-Content (Join-Path $RootDir ".fvmrc") -Raw | ConvertFrom-Json
$FlutterVersion = $FvmConfig.flutter

if ([string]::IsNullOrWhiteSpace($FlutterVersion)) {
  throw "Khong doc duoc version Flutter tu .fvmrc"
}

$FlutterBin = Join-Path $HOME "fvm\versions\$FlutterVersion\bin\flutter.bat"

if (-not (Test-Path $FlutterBin)) {
  throw "Khong tim thay Flutter tai: $FlutterBin"
}

Set-Location $RootDir

Write-Host "Dang dung Flutter $FlutterVersion"
& $FlutterBin pub get
& $FlutterBin build web --release

Write-Host "Build xong tai: $RootDir/build/web"
