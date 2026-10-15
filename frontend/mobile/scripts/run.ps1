param(
    [string]$Device = '',
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
    $runArgs = @('run')
    if (Test-Path -LiteralPath (Join-Path $projectRoot 'config/supabase.local.json')) {
        $runArgs += '--dart-define-from-file=config/supabase.local.json'
    }
    if (-not [string]::IsNullOrWhiteSpace($Device)) {
        $runArgs += @('-d', $Device)
    }
    & $FlutterPath @runArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter run berhenti dengan error.' }
} finally {
    Pop-Location
}
