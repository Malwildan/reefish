param(
    [int]$Port = 4186,
    [string]$FlutterPath = ''
)

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
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get gagal.' }
    $configPath = Join-Path $projectRoot 'config/supabase.local.json'
    $defineArgs = @()
    if (Test-Path -LiteralPath $configPath) {
        $defineArgs = @('--dart-define-from-file=config/supabase.local.json')
    }
    & $FlutterPath run @defineArgs -t tool/preview.dart -d web-server --web-hostname 127.0.0.1 --web-port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Flutter preview berhenti dengan error.' }
} finally {
    Pop-Location
}
