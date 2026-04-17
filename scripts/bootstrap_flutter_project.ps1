if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host "Flutter chua duoc cai dat trong PATH."
  exit 1
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("loan_app_bootstrap_" + [System.Guid]::NewGuid().ToString("N"))
$genDir = Join-Path $tempDir "generated_app"

New-Item -ItemType Directory -Path $genDir -Force | Out-Null

try {
  flutter create $genDir --platforms=android,ios,web --project-name=loan_app_firebase_mvp --org=com.example.loanappfirebase

  Remove-Item android, ios, web -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item .metadata -Force -ErrorAction SilentlyContinue

  Copy-Item (Join-Path $genDir "android") -Destination "android" -Recurse
  Copy-Item (Join-Path $genDir "ios") -Destination "ios" -Recurse
  Copy-Item (Join-Path $genDir "web") -Destination "web" -Recurse
  Copy-Item (Join-Path $genDir ".metadata") -Destination ".metadata"

  flutter pub get

  Write-Host "Da bootstrap xong project Flutter."
  Write-Host "Tiep theo hay chay: flutterfire configure"
}
finally {
  Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
