param([string]$FlutterPath = '')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($FlutterPath)) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($null -ne $flutterCommand) {
        $FlutterPath = $flutterCommand.Source
    } else {
        $installedFlutter = "$env:USERPROFILE/develop/flutter/bin/flutter.bat"
        $portableFlutter = "$env:USERPROFILE/.codex/toolchains/flutter/bin/flutter.bat"
        if (Test-Path -LiteralPath $installedFlutter) { $FlutterPath = $installedFlutter }
        elseif (Test-Path -LiteralPath $portableFlutter) { $FlutterPath = $portableFlutter }
        else { throw 'Flutter SDK belum ditemukan. Tambahkan Flutter ke PATH atau isi -FlutterPath.' }
    }
} elseif (-not (Test-Path -LiteralPath $FlutterPath)) {
    throw "Flutter SDK tidak ditemukan: $FlutterPath"
}
Push-Location -LiteralPath $projectRoot
try {
    & $FlutterPath pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution gagal.' }
    & $FlutterPath analyze
    if ($LASTEXITCODE -ne 0) { throw 'Analisis Flutter gagal.' }
    & $FlutterPath test --reporter expanded
    if ($LASTEXITCODE -ne 0) { throw 'Tes Flutter gagal.' }
    & $FlutterPath build web -t tool/preview.dart --no-web-resources-cdn
    if ($LASTEXITCODE -ne 0) { throw 'Build web gagal.' }
} finally {
    Pop-Location
}
