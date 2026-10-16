param([string]$ConfigPath = 'config/supabase.local.json')
$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$baseUrl = $config.SUPABASE_URL.TrimEnd('/')
$publicKey = $config.SUPABASE_PUBLISHABLE_KEY
if (-not $publicKey) { $publicKey = $config.SUPABASE_ANON_KEY }
if (-not $publicKey) { throw 'Missing public Supabase key.' }
$headers = @{ apikey = $publicKey; Authorization = "Bearer $publicKey" }
$probes = @(
  @{ Name = 'api_me'; Body = @{} },
  @{ Name = 'api_create_boat'; Body = @{ p = @{} } },
  @{ Name = 'api_post_trip'; Body = @{ p = @{} } },
  @{ Name = 'api_list_trips'; Body = @{ p_page = 1; p_limit = 1; p_sort = '-departed_at' } },
  @{ Name = 'api_trip_detail'; Body = @{ p_id = '00000000-0000-0000-0000-000000000000'; p_track = 'none' } }
)
$results = foreach ($probe in $probes) {
  $status = 0
  $body = $null
  try {
    $response = Invoke-WebRequest -Uri "$baseUrl/rest/v1/rpc/$($probe.Name)" -Method Post -Headers $headers -ContentType 'application/json' -Body ($probe.Body | ConvertTo-Json -Depth 5 -Compress) -UseBasicParsing -TimeoutSec 20
    $status = [int]$response.StatusCode
    $body = $response.Content | ConvertFrom-Json
  } catch {
    if (-not $_.Exception.Response) { throw }
    $status = [int]$_.Exception.Response.StatusCode
    try { $body = $_.ErrorDetails.Message | ConvertFrom-Json } catch { }
  }
  [ordered]@{ rpc = $probe.Name; httpStatus = $status; code = $body.code; message = $body.message; missing = ($body.code -eq 'PGRST202') }
}
$results | ConvertTo-Json -Depth 4
if (@($results | Where-Object {
  $_.missing -or
  -not ($_.code -eq '42501' -and $_.httpStatus -in 401,403)
}).Count -gt 0) { exit 1 }
# The anonymous probe must find the RPC and be denied; authenticated behavior is
# checked separately in a rolled-back SQL integration transaction.
