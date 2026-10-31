param([string]$Python = 'python', [string]$UpdateRepo = '')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
Push-Location $taskRoot
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'Dependency restore failed' }
  flutter build windows --release "--dart-define=PENNA_UPDATE_REPO=$UpdateRepo"
  if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
  $taskVersion = (Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version: (.+)').Matches[0].Groups[1].Value.Split('+')[0]
  & $Python 'tool/package_release.py' windows --release-dir 'build/windows/x64/runner/Release' --out "release/PennaComic-$taskVersion-windows-x64.zip"
  if ($LASTEXITCODE -ne 0) { throw 'Packaging failed' }
} finally { Pop-Location }
