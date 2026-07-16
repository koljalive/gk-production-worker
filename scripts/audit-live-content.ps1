param([string]$EnvFile = '.\.env', [switch]$SelfTest)
$ErrorActionPreference = 'Stop'

function Get-VisibleText([string]$Html) {
    $text = [regex]::Replace($Html, '(?is)<script\b.*?</script>|<style\b.*?</style>|<!--.*?-->', ' ')
    $text = [regex]::Replace($text, '(?is)<[^>]+>', ' ')
    return ([Net.WebUtility]::HtmlDecode($text) -replace '\s+', ' ').Trim()
}

function Get-Findings([long]$Id, [string]$Title, [string]$Html) {
    $rows = New-Object Collections.Generic.List[object]
    function Add([string]$Code, [string]$Severity, [string]$Detail) {
        $rows.Add([pscustomobject]@{ id=$Id; title=$Title; code=$Code; severity=$Severity; detail=$Detail })
    }
    $h1 = [regex]::Matches($Html, '(?is)<h1\b[^>]*>.*?</h1>').Count
    if ($h1 -gt 0) { Add 'CONTENT_H1' 'high' "Beitragsinhalt enthält $h1 H1-Überschrift(en)." }
    $headings = [regex]::Matches($Html, '(?is)<h([2-6])\b[^>]*>(?<text>.*?)</h\1>') | ForEach-Object { (Get-VisibleText $_.Groups['text'].Value).ToLowerInvariant() } | Where-Object { $_ }
    $duplicates = @($headings | Group-Object | Where-Object Count -gt 1)
    foreach ($d in $duplicates) { Add 'DUPLICATE_HEADING' 'high' ("Überschrift mehrfach vorhanden ({0}x): {1}" -f $d.Count,$d.Name) }
    $paragraphs = [regex]::Matches($Html, '(?is)<p\b[^>]*>(?<text>.*?)</p>') | ForEach-Object { Get-VisibleText $_.Groups['text'].Value } | Where-Object { $_.Length -ge 80 }
    foreach ($d in @($paragraphs | Group-Object | Where-Object Count -gt 1)) { Add 'DUPLICATE_PARAGRAPH' 'high' ("Absatz mehrfach vorhanden ({0}x): {1}" -f $d.Count,$d.Name.Substring(0,[Math]::Min(140,$d.Name.Length))) }
    $markers = [regex]::Matches($Html, '(?is)<!--\s*(?<marker>(?:GK|AI|SEO|TEMPLATE)[^>]{0,100})-->')
    foreach ($m in $markers) { Add 'TEMPLATE_MARKER' 'medium' $m.Groups['marker'].Value.Trim() }
    $badEncodingChars = @([char]0x00C3, [char]0x00C2, [char]0xFFFD)
    if (@($badEncodingChars | Where-Object { $Html.Contains([string]$_) }).Count -gt 0) { Add 'MOJIBAKE' 'high' 'Verdächtige fehlerhafte Zeichenkodierung gefunden.' }
    if ([regex]::IsMatch($Html, '(?is)<p\b[^>]*>.*?<p\b')) { Add 'NESTED_PARAGRAPH' 'high' 'Verschachtelte Absatz-Tags gefunden.' }
    if ([regex]::IsMatch($Html, '(?is)<h[1-6]\b[^>]*>\s*(?:&nbsp;)?\s*</h[1-6]>')) { Add 'EMPTY_HEADING' 'medium' 'Leere Überschrift gefunden.' }
    $related = [regex]::Matches($Html, '(?is)<a\b[^>]*href\s*=\s*["''](?<url>https?://[^"'']+)["''][^>]*>') | ForEach-Object { [Net.WebUtility]::HtmlDecode($_.Groups['url'].Value).TrimEnd('/') }
    foreach ($d in @($related | Group-Object | Where-Object Count -gt 1)) { Add 'DUPLICATE_LINK_TARGET' 'medium' ("Ziel mehrfach verlinkt ({0}x): {1}" -f $d.Count,$d.Name) }
    return $rows
}

if ($SelfTest) {
    $sample = '<h1>Titel</h1><h2>Test</h2><p>Dies ist ein ausreichend langer doppelter Beispielabsatz für den reproduzierbaren Selbsttest des Inhaltsaudits mit mehr als achtzig Zeichen.</p><h2>Test</h2><p>Dies ist ein ausreichend langer doppelter Beispielabsatz für den reproduzierbaren Selbsttest des Inhaltsaudits mit mehr als achtzig Zeichen.</p><!-- GK_TEMPLATE --><p>kaputt ' + [char]0x00C3 + '</p>'
    $codes = @(Get-Findings 1 'Test' $sample | ForEach-Object code)
    foreach ($required in @('CONTENT_H1','DUPLICATE_HEADING','DUPLICATE_PARAGRAPH','TEMPLATE_MARKER','MOJIBAKE')) { if ($required -notin $codes) { throw "Selbsttest fehlt: $required" } }
    Write-Host 'PASS Live-Content-Audit-Selbsttest'; exit 0
}

if (-not (Test-Path -LiteralPath $EnvFile)) { throw "ENV-Datei fehlt: $EnvFile" }
$v=@{}; Get-Content -LiteralPath $EnvFile | Where-Object {$_ -match '^[^#].*='} | ForEach-Object {$p=$_ -split '=',2;$v[$p[0].Trim()]=$p[1].Trim()}
foreach ($name in @('GK_SITE_URL','GK_SITE_AUDIT_TOKEN','GK_UNIFIED_API_TOKEN')) { if ([string]::IsNullOrWhiteSpace($v[$name])) { throw "$name fehlt." } }
$site=$v['GK_SITE_URL'].TrimEnd('/'); $auditHeaders=@{Authorization='Bearer '+$v['GK_SITE_AUDIT_TOKEN']}; $unifiedHeaders=@{Authorization='Bearer '+$v['GK_UNIFIED_API_TOKEN']}
$items=New-Object Collections.Generic.List[object]; $page=1
do {
    $batch=@(Invoke-RestMethod ($site+'/wp-json/gk-site-audit/v1/items?page='+$page+'&per_page=100') -Headers $auditHeaders)
    if ($batch.Count -eq 1 -and $null -ne $batch[0].items) {$batch=@($batch[0].items)}
    foreach($item in $batch){if($item.id){$items.Add($item)}}; $page++
} while($batch.Count -eq 100)
$findings=New-Object Collections.Generic.List[object]; $scanned=0
foreach($item in ($items|Sort-Object {[long]$_.id} -Unique)){
    $id=[long]$item.id; $body=[Text.Encoding]::UTF8.GetBytes((@{id=$id}|ConvertTo-Json -Compress)); $post=Invoke-RestMethod ($site+'/wp-json/gk-unified-api/v1/read-post') -Method Post -Headers $unifiedHeaders -ContentType 'application/json; charset=utf-8' -Body $body
    foreach($finding in @(Get-Findings $id ([string]$post.title) ([string]$post.content))){$findings.Add($finding)}; $scanned++
}
$root=if(Test-Path (Join-Path $PSScriptRoot '..\GkProductionWorker.sln')){Split-Path -Parent $PSScriptRoot}else{$PSScriptRoot}; $reportDir=Join-Path $root 'reports'; New-Item $reportDir -ItemType Directory -Force|Out-Null; $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$csv=Join-Path $reportDir ('live-content-audit-'+$stamp+'.csv'); $json=Join-Path $reportDir ('live-content-summary-'+$stamp+'.json')
$findings|Export-Csv $csv -NoTypeInformation -Encoding UTF8
$summary=[ordered]@{scanned=$scanned;findings=$findings.Count;affected_posts=@($findings|Select-Object -ExpandProperty id -Unique).Count;by_code=@($findings|Group-Object code|Sort-Object Count -Descending|ForEach-Object{[ordered]@{code=$_.Name;count=$_.Count}})}
$summary|ConvertTo-Json -Depth 5|Set-Content $json -Encoding UTF8
Write-Host ('FERTIG: Geprüft='+$scanned+' | Befunde='+$findings.Count+' | Betroffene Beiträge='+$summary.affected_posts); $summary.by_code|ForEach-Object{Write-Host ($_.code+'='+$_.count)}
