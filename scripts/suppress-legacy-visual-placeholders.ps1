param([string]$EnvFile='.\.env')
$ErrorActionPreference='Stop'
$v=@{};Get-Content $EnvFile|Where-Object{$_-match'^[^#].*='}|ForEach-Object{$p=$_-split'=',2;$v[$p[0].Trim()]=$p[1].Trim()}
foreach($n in @('GK_SITE_URL','GK_SITE_AUDIT_TOKEN','GK_UNIFIED_API_TOKEN')){if([string]::IsNullOrWhiteSpace($v[$n])){throw "$n fehlt."}}
$site=$v.GK_SITE_URL.TrimEnd('/');$ah=@{Authorization='Bearer '+$v.GK_SITE_AUDIT_TOKEN};$uh=@{Authorization='Bearer '+$v.GK_UNIFIED_API_TOKEN}
$items=@();$page=1;do{$b=@(Invoke-RestMethod ($site+'/wp-json/gk-site-audit/v1/items?page='+$page+'&per_page=100') -Headers $ah -TimeoutSec 45);if($b.Count-eq 1-and$null-ne$b[0].items){$b=@($b[0].items)};$items+=$b;$page++}while($b.Count-eq 100)
$marker='gk-legacy-visual-suppression-v1'
$guard='<style id="'+$marker+'">.gkve72-wrap{display:none!important}</style><script>(function(){function r(){document.querySelectorAll(".gkve72-wrap").forEach(function(n){n.remove()})}if(document.readyState==="loading"){document.addEventListener("DOMContentLoaded",r)}else{r()}})();</script>'
$root=Split-Path -Parent $PSScriptRoot;$stamp=Get-Date -Format 'yyyyMMdd-HHmmss';$backup=Join-Path $root('backups\legacy-visual-suppression-'+$stamp);New-Item $backup -ItemType Directory -Force|Out-Null;$changed=0;$verified=0
foreach($i in($items|Sort-Object{[long]$_.id}-Unique)){$id=[long]$i.id;$body=[Text.Encoding]::UTF8.GetBytes((@{id=$id}|ConvertTo-Json -Compress));$p=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body $body;$old=[string]$p.content
 if($old.Contains($marker)){$verified++;continue}
 [IO.File]::WriteAllText((Join-Path $backup("post-$id.html")),$old,[Text.UTF8Encoding]::new($false));$new=$old+"`n"+$guard;$payload=[Text.Encoding]::UTF8.GetBytes((@{id=$id;content=$new}|ConvertTo-Json -Compress));$u=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/update-post') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body $payload;if($u.updated-ne$true){throw "Update nicht bestaetigt: $id"};$q=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body $body;if(-not([string]$q.content).Contains($marker)){throw "Speicherpruefung fehlgeschlagen: $id"};$changed++;$verified++
}
$c=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/clear-cache') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{}'));if($c.cache_cleared-ne$true){throw 'Cache nicht geleert'}
$probe=Invoke-WebRequest ($site+'/apl-tae-signalweg/?_gkverify=1') -UseBasicParsing -Headers @{'User-Agent'='Mozilla/5.0 (Linux; Android 14; Mobile)'} -TimeoutSec 45;if(([string]$probe.Content)-notmatch[regex]::Escape($marker)){throw 'Oeffentliche Unterdrueckung nicht nachweisbar'}
Write-Host("FERTIG: Legacy-Visuals unterdrueckt | Aktualisiert=$changed | Verifiziert=$verified")
