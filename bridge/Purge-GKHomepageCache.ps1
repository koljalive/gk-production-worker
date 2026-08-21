Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$out=[ordered]@{
  checked_utc=(Get-Date).ToUniversalTime().ToString('o')
  purge_url='https://glasfaser-kompass.de/?LSCWP_CTRL=PURGE'
  purge_status=$null
  purge_error=$null
  public_status=$null
  cache_control=$null
  first_image=$null
  has_old_exec=$false
  has_new_ftth=$false
  has_new_content=$false
  has_old_content=$false
}

try {
  $p=Invoke-WebRequest -Uri $out.purge_url -UseBasicParsing -TimeoutSec 60 -Headers @{'Cache-Control'='no-cache';Pragma='no-cache'}
  $out.purge_status=[int]$p.StatusCode
} catch {
  $out.purge_error=$_.Exception.Message
  if ($_.Exception.Response) { try { $out.purge_status=[int]$_.Exception.Response.StatusCode } catch {} }
}

Start-Sleep -Seconds 2
$r=Invoke-WebRequest -Uri 'https://glasfaser-kompass.de/' -UseBasicParsing -TimeoutSec 60 -Headers @{'Cache-Control'='no-cache';Pragma='no-cache'}
$out.public_status=[int]$r.StatusCode
if ($r.Headers['Cache-Control']) { $out.cache_control=[string]$r.Headers['Cache-Control'] }
$h=[string]$r.Content
$m=[regex]::Match($h,'<img\b[^>]*\bsrc=["'']([^"'']+)["'']','IgnoreCase')
if($m.Success){$out.first_image=$m.Groups[1].Value}
$out.has_old_exec=($h -match 'exec-d6f3e553-e01b-4389-8ddd-a9d898b3c715')
$out.has_new_ftth=($h -match 'ftth-abschluss-reales-foto')
$out.has_new_content=($h -match 'Praxiswissen statt Werbeversprechen')
$out.has_old_content=($h -match 'Praxiswissen aus dem Telekommunikations-Alltag')

$json=$out|ConvertTo-Json -Depth 6
[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-homepage-cache-purge-result.json'),$json,(New-Object Text.UTF8Encoding($false)))
Write-Host $json
