param(
    [string]$GoPath = 'go',
    [ValidateRange(1, 65535)]
    [int]$Port = 8080,
    [string]$AllowedOrigin = 'http://127.0.0.1:4195'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$configPath = Join-Path $repoRoot 'frontend\mobile\config\supabase.local.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($config.SUPABASE_URL) -or
    [string]::IsNullOrWhiteSpace($config.SUPABASE_PUBLISHABLE_KEY)) {
    throw 'supabase.local.json must define SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.'
}

$goCommand = Get-Command -Name $GoPath -CommandType Application -ErrorAction SilentlyContinue
if ($null -eq $goCommand -and -not (Test-Path -LiteralPath $GoPath -PathType Leaf)) {
    throw "Go executable not found: $GoPath. Supply -GoPath with the executable path."
}

$savedEnvironment = @{
    SUPABASE_URL = $env:SUPABASE_URL
    SUPABASE_ANON_KEY = $env:SUPABASE_ANON_KEY
    PORT = $env:PORT
    ALLOWED_ORIGIN = $env:ALLOWED_ORIGIN
}

try {
    $env:SUPABASE_URL = [string]$config.SUPABASE_URL
    $env:SUPABASE_ANON_KEY = [string]$config.SUPABASE_PUBLISHABLE_KEY
    $env:PORT = [string]$Port
    $env:ALLOWED_ORIGIN = $AllowedOrigin
    Write-Host "Starting Reefish API from $repoRoot\backend\api on port $Port."
    Push-Location (Join-Path $repoRoot 'backend\api')
    try {
        & $GoPath run ./cmd/api
        if ($LASTEXITCODE -ne 0) {
            throw "Go API stopped with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    foreach ($name in $savedEnvironment.Keys) {
        $value = $savedEnvironment[$name]
        if ($null -eq $value) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }
        else {
            Set-Item -LiteralPath "Env:$name" -Value $value
        }
    }
}
