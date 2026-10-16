param(
    [int]$Port = 4194,
    [string]$ProjectConfig = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($ProjectConfig)) {
    $ProjectConfig = Join-Path $projectRoot 'config/supabase.local.json'
}
if (-not (Test-Path -LiteralPath $ProjectConfig)) {
    throw 'Config Supabase lokal tidak ditemukan.'
}

$config = Get-Content -LiteralPath $ProjectConfig -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($config.SUPABASE_URL) -or
    [string]::IsNullOrWhiteSpace($config.SUPABASE_PUBLISHABLE_KEY)) {
    throw 'URL atau publishable key Supabase kosong.'
}

$preview = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/?screen=departure&demo-grid-locks=1" -UseBasicParsing
if ($preview.StatusCode -ne 200) { throw 'Preview tidak merespons HTTP 200.' }

$settingsUri = ([Uri]$config.SUPABASE_URL).AbsoluteUri.TrimEnd('/') + '/auth/v1/settings'
$response = Invoke-WebRequest -Uri $settingsUri -Headers @{
    apikey = $config.SUPABASE_PUBLISHABLE_KEY
} -UseBasicParsing
$settings = $response.Content | ConvertFrom-Json
if ($response.StatusCode -ne 200) { throw 'Supabase Auth settings tidak merespons HTTP 200.' }

[pscustomobject]@{
    PreviewStatus = $preview.StatusCode
    AuthSettingsStatus = $response.StatusCode
    PhoneProviderEnabled = [bool]$settings.external.phone
    EmailProviderEnabled = [bool]$settings.external.email
    CredentialsPrinted = $false
} | ConvertTo-Json
