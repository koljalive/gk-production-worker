Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Get-PlainSecret([string]$Path){$s=Get-Content $Path|ConvertTo-SecureString;$p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s);try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}}
function Invoke-WpJson([string]$Method,[string]$Path,[hashtable]$Headers,[object]$Body=$null){$params=@{Uri=('https://glasfaser-kompass.de/wp-json'+$Path);Method=$Method;Headers=$Headers;UseBasicParsing=$true;TimeoutSec=180};if($null-ne$Body){$json=$Body|ConvertTo-Json -Depth 40 -Compress;$params.Body=[Text.Encoding]::UTF8.GetBytes($json);$params.ContentType='application/json; charset=utf-8'};$response=Invoke-WebRequest @params;if([string]::IsNullOrWhiteSpace([string]$response.Content)){return $null};[string]$response.Content|ConvertFrom-Json}
function Capture([string]$Url,[string]$Path,[int]$Width,[int]$Height){$candidates=@("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe");$chrome=$candidates|Where-Object{Test-Path $_}|Select-Object -First 1;if(-not$chrome){throw 'Chrome not found'};& $chrome --headless=new --disable-gpu --hide-scrollbars --window-size="$Width,$Height" --screenshot="$Path" $Url|Out-Null;if(-not(Test-Path $Path)){throw "Screenshot missing: $Path"}}
function Save-Result([object]$Value){$path=Join-Path $env:GITHUB_WORKSPACE 'bridge/direct-live-improvements-result.json';[IO.File]::WriteAllText($path,($Value|ConvertTo-Json -Depth 40),(New-Object Text.UTF8Encoding($false)))}
$secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel'
$user=(Get-Content(Join-Path $secretDir 'wp-user.txt')-Raw).Trim()
$pass=Get-PlainSecret(Join-Path $secretDir 'wp-password.dat')
try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($user+':'+$pass))}finally{Remove-Variable pass -ErrorAction SilentlyContinue}
$headers=@{Authorization="Basic $basic";Accept='application/json'};Remove-Variable basic -ErrorAction SilentlyContinue
$targets=@(
[ordered]@{id=21005;slug='dsl-kupfer';url='https://glasfaser-kompass.de/dsl-kupfer/';media=29398;eyebrow='DSL & Kupfer';title='Schneller zur richtigen Antwort';text='Von Anschluss und Hausverkabelung bis Störung: Hier finden Sie die wichtigsten DSL-Themen ohne Umwege.';links=@(@('DSL-Störungen prüfen','/dsl-stoerungen-verstehen/'),@('Hausverkabelung prüfen','/hausverkabelung-pruefen-dsl/'),@('DSL oder Glasfaser?','/glasfaser-oder-dsl/'))},
[ordered]@{id=21009;slug='praxiswissen';url='https://glasfaser-kompass.de/praxiswissen/';media=29398;eyebrow='Praxiswissen';title='Konkrete Hilfe für den Anschluss';text='Verständliche Checklisten und Anleitungen für Vorbereitung, Installation und Fehlersuche.';links=@(@('Technikertermin vorbereiten','/technikertermin-dsl-vorbereiten/'),@('Hausanschluss verstehen','/glasfaser-hausanschluss/'),@('Störungen eingrenzen','/stoerungen/'))},
[ordered]@{id=21008;slug='stoerungen';url='https://glasfaser-kompass.de/stoerungen/';media=29403;eyebrow='Störungshilfe';title='Problem Schritt für Schritt eingrenzen';text='Starten Sie beim Anschluss, prüfen Sie danach Router und Heimnetz – so vermeiden Sie unnötige Maßnahmen.';links=@(@('DSL-Störung','/dsl-stoerungen-verstehen/'),@('WLAN-Störquellen','/wlan-stoerquellen-erklaert/'),@('Hausverkabelung','/hausverkabelung-pruefen-dsl/'))},
[ordered]@{id=1009;slug='technik-lexikon';url='https://glasfaser-kompass.de/technik-lexikon-2/';media=29401;eyebrow='Technik-Lexikon';title='Begriffe schneller finden und verstehen';text='Die wichtigsten Begriffe zu Glasfaser, DSL und Heimnetz – kompakt erklärt und thematisch geordnet.';links=@(@('Glasfaser-Grundlagen','/glasfaser/'),@('DSL & Kupfer','/dsl-kupfer/'),@('Router-Wissen','/router-kaufberatung/'))}
)
$backupDir='C:\GKBridge\backups';New-Item -ItemType Directory -Force -Path $backupDir|Out-Null
$shotDir=Join-Path $env:GITHUB_WORKSPACE 'bridge/direct-live-evidence';New-Item -ItemType Directory -Force -Path $shotDir|Out-Null
$run=[ordered]@{started_utc=(Get-Date).ToUniversalTime().ToString('o');status='RUNNING';changed=@();verified=@();backups=@();error=$null}
try{
$beforeById=@{}
foreach($t in $targets){$before=Invoke-WpJson 'GET' "/wp/v2/pages/$($t.id)?context=edit&_fields=id,modified,title,link,content,featured_media" $headers;$beforeById[[string]$t.id]=$before;$backupPath=Join-Path $backupDir("direct-live-$($t.id)-"+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json');[IO.File]::WriteAllText($backupPath,($before|ConvertTo-Json -Depth 40),(New-Object Text.UTF8Encoding($false)));$run.backups+=$backupPath}
foreach($t in $targets){
$before=$beforeById[[string]$t.id]
$media=Invoke-WpJson 'GET' "/wp/v2/media/$($t.media)?context=edit&_fields=id,source_url,alt_text,title,media_type,mime_type" $headers
if([string]$media.media_type-ne'image'-or[string]$media.mime_type-notmatch'^image/(jpeg|webp)$'){throw "Unsafe media $($t.media)"}
$src=[string]$media.source_url;$alt=[string]$media.alt_text;if([string]::IsNullOrWhiteSpace($alt)){$alt=[string]$media.title.rendered}
$raw=[string]$before.content.raw
$raw=[regex]::Replace($raw,'(?is)<!--\s*wp:image\b.*?<!--\s*\/wp:image\s*-->','',{param($m)if($m.Value-match'(?i)\.svg|exec-|schematic|diagramm|illustration'){''}else{$m.Value}})
$raw=[regex]::Replace($raw,'(?is)<figure\b[^>]*>.*?<\/figure>','',{param($m)if($m.Value-match'(?i)\.svg|exec-|schematic|diagramm|illustration'){''}else{$m.Value}})
$links=($t.links|ForEach-Object{'<a href="'+$_[1]+'" style="display:inline-flex;align-items:center;padding:10px 14px;border-radius:999px;background:#fff;color:#0b4f6c;text-decoration:none;font-weight:700;border:1px solid #b9d8e8;">'+$_[0]+'</a>'})-join''
$block='<!-- gk-direct-live-v1:'+$t.slug+' --><section style="margin:24px 0 32px;padding:clamp(22px,4vw,36px);border-radius:20px;background:linear-gradient(135deg,#edf8fc 0%,#f7fbfd 100%);border:1px solid #c8e2ee;box-shadow:0 10px 30px rgba(20,77,104,.08);"><p style="margin:0 0 8px;color:#087e8b;font-size:.82rem;font-weight:800;letter-spacing:.08em;text-transform:uppercase;">'+$t.eyebrow+'</p><h2 style="margin:0 0 10px;color:#123b4a;font-size:clamp(1.35rem,3vw,2rem);line-height:1.18;">'+$t.title+'</h2><p style="margin:0 0 18px;color:#355866;font-size:1.05rem;line-height:1.65;">'+$t.text+'</p><nav aria-label="Direkteinstiege" style="display:flex;flex-wrap:wrap;gap:10px;">'+$links+'</nav></section><!-- wp:image {"id":'+$t.media+',"sizeSlug":"large","linkDestination":"none","align":"wide"} --><figure class="wp-block-image alignwide size-large"><img src="'+$src+'" alt="'+[Net.WebUtility]::HtmlEncode($alt)+'" class="wp-image-'+$t.media+'"/></figure><!-- /wp:image -->'
if($raw-match'<!-- gk-direct-live-v1:'){$raw=[regex]::Replace($raw,'(?is)<!-- gk-direct-live-v1:'+ [regex]::Escape($t.slug) +' -->.*?<!-- /wp:image -->',$block,1)}else{$raw=$block+$raw}
Invoke-WpJson 'POST' "/wp/v2/pages/$($t.id)" $headers([ordered]@{content=$raw;featured_media=$t.media})|Out-Null
$run.changed+=[ordered]@{id=$t.id;url=$t.url;media_id=$t.media;image=$src;improvement='visual guide, direct links, contextual image, schematic cleanup'}
}
foreach($t in $targets){
$public=Invoke-WebRequest -Uri $t.url -UseBasicParsing -TimeoutSec 180 -Headers @{'Cache-Control'='no-cache';Pragma='no-cache'};$html=[string]$public.Content
$h1=([regex]::Matches($html,'<h1\b','IgnoreCase')).Count;$marker=$html.Contains("gk-direct-live-v1:$($t.slug)");$bad=([regex]::Matches($html,'(?i)(\.svg|exec-|schematic|diagramm|illustration)')).Count
$change=$run.changed|Where-Object id-eq$t.id|Select-Object -First 1;$stem=[IO.Path]::GetFileNameWithoutExtension(([uri][string]$change.image).AbsolutePath);$visible=$html-match[regex]::Escape($stem)
if([int]$public.StatusCode-ne200-or-not$marker-or$h1-ne1-or-not$visible-or$bad-gt0){throw "Public acceptance failed $($t.id): marker=$marker h1=$h1 image=$visible bad=$bad"}
$desktop=Join-Path $shotDir "$($t.slug)-desktop.png";$mobile=Join-Path $shotDir "$($t.slug)-mobile.png";Capture $t.url $desktop 1440 1400;Capture $t.url $mobile 390 844
$run.verified+=[ordered]@{id=$t.id;url=$t.url;http=200;h1_count=$h1;image_visible=$visible;schematic_markers=$bad;desktop="bridge/direct-live-evidence/$($t.slug)-desktop.png";mobile="bridge/direct-live-evidence/$($t.slug)-mobile.png"}
}
$run.status='SUCCEEDED';$run.finished_utc=(Get-Date).ToUniversalTime().ToString('o');Save-Result $run
}catch{$run.status='FAILED';$run.error=$_.Exception.Message;$run.finished_utc=(Get-Date).ToUniversalTime().ToString('o');Save-Result $run;throw}
