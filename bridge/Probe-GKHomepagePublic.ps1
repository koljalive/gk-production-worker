Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$stamp=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$url="https://glasfaser-kompass.de/?gk_nocache=$stamp"
$r=Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 120 -Headers @{'Cache-Control'='no-cache, no-store, max-age=0';'Pragma'='no-cache';'User-Agent'='GK-Visual-Probe/1.0'}
$html=[string]$r.Content
$imgs=@([regex]::Matches($html,'<img\b[^>]*>','IgnoreCase')|ForEach-Object{
  $tag=$_.Value
  [pscustomobject]@{
    src=([regex]::Match($tag,'\bsrc=["'']([^"'']+)["'']','IgnoreCase')).Groups[1].Value
    alt=([regex]::Match($tag,'\balt=["'']([^"'']*)["'']','IgnoreCase')).Groups[1].Value
  }
})
$out=[ordered]@{
  checked_utc=(Get-Date).ToUniversalTime().ToString('o')
  url=$url
  status=[int]$r.StatusCode
  cache_control=[string]$r.Headers['Cache-Control']
  age=[string]$r.Headers['Age']
  x_litespeed_cache=[string]$r.Headers['X-LiteSpeed-Cache']
  first_images=@($imgs|Select-Object -First 8)
  has_old_exec=($html -match 'exec-d6f3e553-e01b-4389-8ddd-a9d898b3c715')
  has_new_ftth=($html -match 'ftth-abschluss-reales-foto')
  has_new_content=($html -match 'Praxiswissen statt Werbeversprechen')
  has_old_content=($html -match 'Praxiswissen aus dem Telekommunikations-Alltag')
}
$json=$out|ConvertTo-Json -Depth 8
[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-homepage-public-probe.json'),$json,(New-Object Text.UTF8Encoding($false)))
Write-Host $json