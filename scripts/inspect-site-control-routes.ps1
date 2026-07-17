param([string]$EnvFile='.\.env')
$ErrorActionPreference='Stop';$v=@{};Get-Content $EnvFile|Where-Object{$_-match'^[^#].*='}|ForEach-Object{$p=$_-split'=',2;$v[$p[0].Trim()]=$p[1].Trim()};$site=$v.GK_SITE_URL.TrimEnd('/');$control=@{Authorization='Bearer '+$v.GK_CONTROL_TOKEN}
$index=Invoke-RestMethod ($site+'/wp-json/') -TimeoutSec 45
$index.routes.PSObject.Properties|Where-Object{$_.Name-match'(?i)(visual|object|plugin|setting|option|css|control|unified)'}|ForEach-Object{Write-Host('ROUTE '+$_.Name+' '+(($_.Value.methods|ForEach-Object{$_})-join','))}
$mobile=@{'User-Agent'='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/126.0 Mobile Safari/537.36'};$page=Invoke-WebRequest ($site+'/apl-tae-signalweg/?_probe=1') -UseBasicParsing -Headers $mobile -TimeoutSec 45;$html=[string]$page.Content
foreach($m in [regex]::Matches($html,'(?is).{0,350}<img\b[^>]+gk-visual-engine-72[^>]*>.{0,350}')){Write-Host('VISUAL_CONTEXT '+(($m.Value-replace'\s+',' ').Trim()))}
try{$plugins=Invoke-RestMethod ($site+'/wp-json/wp/v2/plugins?context=edit&per_page=100') -Headers $control -TimeoutSec 45;foreach($p in @($plugins)){if(([string]$p.plugin+[string]$p.name)-match'(?i)(visual|object|gk)'){Write-Host('PLUGIN '+($p|ConvertTo-Json -Compress -Depth 5))}}}catch{$code=0;if($_.Exception.Response){$code=[int]$_.Exception.Response.StatusCode};Write-Host("PLUGIN_ACCESS HTTP=$code")}
