param([string]$EnvFile='.\.env')
$ErrorActionPreference='Stop'
$v=@{};Get-Content $EnvFile|Where-Object{$_-match'^[^#].*='}|ForEach-Object{$p=$_-split'=',2;$v[$p[0].Trim()]=$p[1].Trim()}
foreach($n in @('GK_SITE_URL','GK_SITE_AUDIT_TOKEN','GK_UNIFIED_API_TOKEN')){if([string]::IsNullOrWhiteSpace($v[$n])){throw "$n fehlt."}}
$site=$v.GK_SITE_URL.TrimEnd('/');$audit=@{Authorization='Bearer '+$v.GK_SITE_AUDIT_TOKEN};$unified=@{Authorization='Bearer '+$v.GK_UNIFIED_API_TOKEN}
$queue=@();$page=1;do{$batch=@(Invoke-RestMethod ($site+'/wp-json/gk-site-audit/v1/items?page='+$page+'&per_page=100') -Headers $audit -TimeoutSec 45);if($batch.Count-eq1-and$null-ne$batch[0].items){$batch=@($batch[0].items)};$queue+=$batch;$page++}while($batch.Count-eq100)
$ids=@($queue|Where-Object{$null-ne$_.id}|ForEach-Object{[long]$_.id}|Sort-Object -Unique);$rows=@()
foreach($id in $ids){$body=[Text.Encoding]::UTF8.GetBytes((@{id=$id}|ConvertTo-Json -Compress));$p=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $unified -ContentType 'application/json; charset=utf-8' -Body $body;$html=[string]$p.content;$plain=([Net.WebUtility]::HtmlDecode([regex]::Replace($html,'(?is)<[^>]+>',' ')))-replace'\s+',' ';if(([string]$p.title+' '+$plain)-notmatch'(?i)\b(APL|TAE|DSL.Signalweg|Signalweg.DSL|Endleitung|Hausverkabelung)\b'){continue}
 $images=@();foreach($m in [regex]::Matches($html,'(?is)<img\b(?<a>[^>]*)>')){$a=$m.Groups['a'].Value;$src=[regex]::Match($a,'(?is)\bsrc=["''](?<v>[^"'']+)').Groups['v'].Value;$alt=[regex]::Match($a,'(?is)\balt=["''](?<v>[^"'']*)').Groups['v'].Value;$images+=@{src=$src;alt=$alt}}
 $snips=@();foreach($m in [regex]::Matches($html,'(?is)<(?:p|li|td|th|h[2-4])\b[^>]*>(?<v>.*?)</(?:p|li|td|th|h[2-4])>')){$s=(([Net.WebUtility]::HtmlDecode([regex]::Replace($m.Groups['v'].Value,'<[^>]+>',' ')))-replace'\s+',' ').Trim();if($s-match'(?i)\b(APL|TAE|Signalweg|Endleitung|DSLAM|MSAN|KVz|MFG|HVt)\b'){$snips+=$s}}
 $rows+=[pscustomobject]@{id=$id;title=[string]$p.title;images=$images;snippets=@($snips|Select-Object -Unique)};Write-Host('DSL_AUDIT '+($rows[-1]|ConvertTo-Json -Compress -Depth 8))
}
$root=Split-Path -Parent $PSScriptRoot;$out=Join-Path $root 'reports';New-Item $out -ItemType Directory -Force|Out-Null;$rows|ConvertTo-Json -Depth 8|Set-Content (Join-Path $out('dsl-signal-audit-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.json')) -Encoding UTF8;Write-Host("FERTIG: DSL/APL/TAE-Seiten=$($rows.Count)")
