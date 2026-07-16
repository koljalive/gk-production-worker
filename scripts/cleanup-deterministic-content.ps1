param(
    [ValidateSet('Preview','Apply')][string]$Mode='Preview',
    [string]$Confirm='',
    [string]$EnvFile='.\.env',
    [switch]$SelfTest
)
$ErrorActionPreference='Stop'

function Visible([string]$value){
    return (([Net.WebUtility]::HtmlDecode([regex]::Replace($value,'(?is)<[^>]+>',' '))) -replace '\s+',' ').Trim()
}

function Clean([string]$source){
    $markerCount=[regex]::Matches($source,'(?is)<!--\s*(?:GK|AI|SEO|TEMPLATE)[^>]{0,200}-->').Count
    $clean=[regex]::Replace($source,'(?is)<!--\s*(?:GK|AI|SEO|TEMPLATE)[^>]{0,200}-->','')
    $seen=@{}; $removed=New-Object Collections.Generic.List[string]
    $clean=[regex]::Replace($clean,'(?is)<p\b[^>]*>.*?</p>',{
        param($m)
        $text=(Visible $m.Value).ToLowerInvariant()
        if($text.Length -lt 80){return $m.Value}
        if($seen.ContainsKey($text)){$removed.Add($text);return ''}
        $seen[$text]=$true; return $m.Value
    })
    return [pscustomobject]@{html=$clean;markers=$markerCount;duplicates=$removed.Count}
}

function Assert-Cleanup([string]$before,[object]$result){
    $again=Clean $result.html
    if($again.html -cne $result.html){throw 'Bereinigung ist nicht idempotent.'}
    if([regex]::Matches($result.html,'(?is)<!--\s*(?:GK|AI|SEO|TEMPLATE)[^>]{0,200}-->').Count -ne 0){throw 'Template-Marker verblieben.'}
    $beforeLinks=@([regex]::Matches($before,'(?is)<a\b[^>]*href\s*=\s*["''](?<u>.*?)["'']')|ForEach-Object{$_.Groups['u'].Value})
    $afterLinks=@([regex]::Matches($result.html,'(?is)<a\b[^>]*href\s*=\s*["''](?<u>.*?)["'']')|ForEach-Object{$_.Groups['u'].Value})
    if(($beforeLinks -join "`n") -cne ($afterLinks -join "`n")){throw 'Linkziele wurden verändert.'}
}

if($SelfTest){
    $p='<p>Dieser identische Testabsatz enthält bewusst mehr als achtzig Zeichen und darf bei der sicheren Bereinigung exakt einmal übrig bleiben.</p>'
    $sample='<!-- GK_UPGRADE_START -->'+$p+'<h2>Bleibt</h2>'+$p+'<a href="https://example.org/x">X</a>'
    $r=Clean $sample; Assert-Cleanup $sample $r
    if($r.markers -ne 1 -or $r.duplicates -ne 1 -or ([regex]::Matches($r.html,'identische Testabsatz').Count -ne 1)){throw 'Selbsttest ergab falsche Zählwerte.'}
    Write-Host 'PASS deterministische Inhaltsbereinigung';exit 0
}

if($Mode -eq 'Apply' -and $Confirm -cne 'DETERMINISTISCHE BEREINIGUNG'){throw 'Apply erfordert -Confirm "DETERMINISTISCHE BEREINIGUNG".'}
if(-not(Test-Path -LiteralPath $EnvFile)){throw "ENV-Datei fehlt: $EnvFile"}
$v=@{};Get-Content -LiteralPath $EnvFile|Where-Object{$_ -match '^[^#].*='}|ForEach-Object{$p=$_ -split '=',2;$v[$p[0].Trim()]=$p[1].Trim()}
foreach($name in @('GK_SITE_URL','GK_SITE_AUDIT_TOKEN','GK_UNIFIED_API_TOKEN')){if([string]::IsNullOrWhiteSpace($v[$name])){throw "$name fehlt."}}
$site=$v['GK_SITE_URL'].TrimEnd('/');$ah=@{Authorization='Bearer '+$v['GK_SITE_AUDIT_TOKEN']};$uh=@{Authorization='Bearer '+$v['GK_UNIFIED_API_TOKEN']}
$items=New-Object Collections.Generic.List[object];$page=1
do{$batch=@(Invoke-RestMethod($site+'/wp-json/gk-site-audit/v1/items?page='+$page+'&per_page=100')-Headers $ah);if($batch.Count -eq 1 -and $null -ne $batch[0].items){$batch=@($batch[0].items)};foreach($i in $batch){if($i.id){$items.Add($i)}};$page++}while($batch.Count -eq 100)
$root=if(Test-Path(Join-Path $PSScriptRoot '..\GkProductionWorker.sln')){Split-Path -Parent $PSScriptRoot}else{$PSScriptRoot};$stamp=Get-Date -Format 'yyyyMMdd-HHmmss';$reportDir=Join-Path $root 'reports';$backupDir=Join-Path $root('backups\deterministic-'+$stamp);New-Item $reportDir -ItemType Directory -Force|Out-Null;if($Mode -eq 'Apply'){New-Item $backupDir -ItemType Directory -Force|Out-Null}
$rows=New-Object Collections.Generic.List[object]
foreach($item in($items|Sort-Object{[long]$_.id}-Unique)){
    $id=[long]$item.id;$readBody=[Text.Encoding]::UTF8.GetBytes((@{id=$id}|ConvertTo-Json -Compress))
    $post=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body $readBody
    $old=[string]$post.content;$result=Clean $old;Assert-Cleanup $old $result
    if($result.html -ceq $old){continue};$status='READY'
    if($Mode -eq 'Apply'){
        [IO.File]::WriteAllText((Join-Path $backupDir("post-$id.html")),$old,[Text.UTF8Encoding]::new($false));$payload=[Text.Encoding]::UTF8.GetBytes((@{id=$id;content=$result.html}|ConvertTo-Json -Compress))
        $updated=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/update-post') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body $payload
        if($updated.updated -ne $true){throw "Update $id nicht bestätigt"}
        $verify=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body $readBody
        if([string]$verify.content -cne $result.html){throw "Speicherprüfung $id fehlgeschlagen"};$status='UPDATED_AND_VERIFIED'
    }
    $rows.Add([pscustomobject]@{id=$id;title=[string]$post.title;markers_removed=$result.markers;duplicate_paragraphs_removed=$result.duplicates;status=$status});Write-Host("${id}: $status | Marker="+$result.markers+' | Dubletten='+$result.duplicates)
}
if($Mode -eq 'Apply' -and $rows.Count){$cache=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/clear-cache') -Method Post -Headers $uh -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{}'));if($cache.cache_cleared -ne $true){throw 'Cache-Leerung nicht bestätigt'}}
$report=Join-Path $reportDir('deterministic-cleanup-'+$Mode.ToLowerInvariant()+'-'+$stamp+'.csv');$rows|Export-Csv $report -NoTypeInformation -Encoding UTF8;Write-Host('FERTIG: Modus='+$Mode+' | Beiträge='+$rows.Count+' | Marker='+(@($rows|Measure-Object markers_removed -Sum).Sum)+' | Dubletten='+(@($rows|Measure-Object duplicate_paragraphs_removed -Sum).Sum))
