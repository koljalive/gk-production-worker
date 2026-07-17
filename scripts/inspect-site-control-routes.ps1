param([string]$EnvFile='.\.env')
$ErrorActionPreference='Stop';$v=@{};Get-Content $EnvFile|Where-Object{$_-match'^[^#].*='}|ForEach-Object{$p=$_-split'=',2;$v[$p[0].Trim()]=$p[1].Trim()};$site=$v.GK_SITE_URL.TrimEnd('/')
$index=Invoke-RestMethod ($site+'/wp-json/') -TimeoutSec 45
$index.routes.PSObject.Properties|Where-Object{$_.Name-match'(?i)(visual|object|plugin|setting|option|css|control|unified)'}|ForEach-Object{Write-Host('ROUTE '+$_.Name+' '+(($_.Value.methods|ForEach-Object{$_})-join','))}
$mobile=@{'User-Agent'='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/126.0 Mobile Safari/537.36'};$page=Invoke-WebRequest ($site+'/apl-tae-signalweg/?_probe=1') -UseBasicParsing -Headers $mobile -TimeoutSec 45;$html=[string]$page.Content
foreach($m in [regex]::Matches($html,'(?is).{0,350}<img\b[^>]+gk-visual-engine-72[^>]*>.{0,350}')){Write-Host('VISUAL_CONTEXT '+(($m.Value-replace'\s+',' ').Trim()))}
