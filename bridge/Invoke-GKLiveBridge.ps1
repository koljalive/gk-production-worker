param(
    [Parameter(Mandatory=$true)][string]$RequestPath,
    [Parameter(Mandatory=$true)][string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-JsonUtf8NoBom {
    param([string]$Path, [object]$Value)
    $json = $Value | ConvertTo-Json -Depth 50
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $enc)
}
function Get-PlainSecret([string]$Path) {
    $secure = Get-Content $Path | ConvertTo-SecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
function Get-Sha256([string]$Text) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $bytes=[Text.Encoding]::UTF8.GetBytes($Text); return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Invoke-Wp {
    param([string]$Method,[string]$Url,[hashtable]$Headers,[object]$Body=$null)
    $params=@{Uri=$Url;Method=$Method;Headers=$Headers;UseBasicParsing=$true;TimeoutSec=120}
    if($null-ne$Body){$json=$Body|ConvertTo-Json -Depth 50 -Compress;$params.Body=[Text.Encoding]::UTF8.GetBytes($json);$params.ContentType='application/json; charset=utf-8'}
    try{$r=Invoke-WebRequest @params;return [pscustomobject]@{ok=$true;status=[int]$r.StatusCode;content_type=[string]$r.Headers['Content-Type'];body=[string]$r.Content;error=$null}}
    catch{$status=$null;$bodyText='';if($_.Exception.Response){try{$status=[int]$_.Exception.Response.StatusCode}catch{};try{$reader=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream());$bodyText=$reader.ReadToEnd();$reader.Close()}catch{}};return [pscustomobject]@{ok=$false;status=$status;content_type=$null;body=$bodyText;error=$_.Exception.Message}}
}

$result=[ordered]@{bridge_version='1.1.1';executed_at_utc=(Get-Date).ToUniversalTime().ToString('o');request=$null;success=$false;preflight=$null;response=$null;backup=$null;error=$null}

try{
    if(-not(Test-Path $RequestPath)){throw "Request file not found: $RequestPath"}
    $requestJson=[IO.File]::ReadAllText($RequestPath,[Text.Encoding]::UTF8)
    $request=$requestJson|ConvertFrom-Json
    $result.request=$request
    $action=[string]$request.action
    if($action -notin @('get','post','upload_media_url')){throw "Unsupported action '$action'. Allowed: get, post, upload_media_url."}

    $secretDir=Join-Path $env:APPDATA 'GK-MCP-Tunnel'
    $userFile=Join-Path $secretDir 'wp-user.txt';$passFile=Join-Path $secretDir 'wp-password.dat'
    if(-not(Test-Path $userFile)){throw "Missing WordPress username file: $userFile"}
    if(-not(Test-Path $passFile)){throw "Missing WordPress password file: $passFile"}
    $wpUser=(Get-Content $userFile -Raw).Trim();$wpPass=Get-PlainSecret $passFile
    try{$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$wpUser`:$wpPass"))}finally{Remove-Variable wpPass -ErrorAction SilentlyContinue}
    $headers=@{Authorization="Basic $basic";Accept='application/json'}
    Remove-Variable basic -ErrorAction SilentlyContinue
    $base='https://glasfaser-kompass.de/wp-json'

    if($action -eq 'upload_media_url'){
        $source=[string]$request.source_url
        if([string]::IsNullOrWhiteSpace($source)){throw 'upload_media_url requires source_url.'}
        $uri=[Uri]$source
        if($uri.Scheme -ne 'https'){throw 'Media source must use HTTPS.'}
        if($uri.Host -notin @('commons.wikimedia.org','upload.wikimedia.org')){throw "Media source host not allow-listed: $($uri.Host)"}
        $filename=if($request.PSObject.Properties.Name -contains 'filename' -and -not [string]::IsNullOrWhiteSpace([string]$request.filename)){[string]$request.filename}else{[IO.Path]::GetFileName($uri.AbsolutePath)}
        if([string]::IsNullOrWhiteSpace($filename)){throw 'Could not determine media filename.'}
        $ext=[IO.Path]::GetExtension($filename).ToLowerInvariant()
        $mime=switch($ext){'.jpg'{'image/jpeg'}'.jpeg'{'image/jpeg'}'.png'{'image/png'}'.webp'{'image/webp'}default{throw "Unsupported media extension: $ext"}}
        $tmp=Join-Path $env:TEMP ("gk-media-"+[Guid]::NewGuid().ToString('N')+$ext)
        try{
            Invoke-WebRequest -Uri $source -OutFile $tmp -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 180 -Headers @{'User-Agent'='Glasfaser-Kompass/1.0 image import'}
            if(-not(Test-Path $tmp)){throw 'Downloaded media file missing.'}
            $bytes=[IO.File]::ReadAllBytes($tmp)
            if($bytes.Length -lt 1024){throw "Downloaded media file unexpectedly small: $($bytes.Length) bytes"}
            $upHeaders=@{Authorization=$headers.Authorization;Accept='application/json';'Content-Disposition'=('attachment; filename="{0}"' -f $filename)}
            try{$up=Invoke-WebRequest -Uri ($base+'/wp/v2/media') -Method POST -Headers $upHeaders -Body $bytes -ContentType $mime -UseBasicParsing -TimeoutSec 180}
            catch{throw "WordPress media upload failed: $($_.Exception.Message)"}
            $obj=[string]$up.Content|ConvertFrom-Json
            $mid=[int]$obj.id
            if($mid -le 0){throw 'WordPress media upload returned no media ID.'}
            $meta=[ordered]@{}
            if($request.PSObject.Properties.Name -contains 'title'){$meta.title=[string]$request.title}
            if($request.PSObject.Properties.Name -contains 'alt_text'){$meta.alt_text=[string]$request.alt_text}
            if($request.PSObject.Properties.Name -contains 'caption'){$meta.caption=[string]$request.caption}
            if($request.PSObject.Properties.Name -contains 'description'){$meta.description=[string]$request.description}
            if($meta.Count -gt 0){$mr=Invoke-Wp -Method 'POST' -Url ($base+"/wp/v2/media/$mid") -Headers $headers -Body $meta;if(-not $mr.ok){throw "Media metadata update failed HTTP $($mr.status): $($mr.body)"};$obj=$mr.body|ConvertFrom-Json}
            $result.response=[ordered]@{ok=$true;status=[int]$up.StatusCode;media_id=$mid;source_url=[string]$obj.source_url;mime_type=[string]$obj.mime_type;alt_text=[string]$obj.alt_text;caption=[string]$obj.caption.rendered;bytes=$bytes.Length}
            $result.success=$true
        } finally {Remove-Item $tmp -Force -ErrorAction SilentlyContinue}
    }
    else{
        $path=[string]$request.path
        if([string]::IsNullOrWhiteSpace($path)){throw 'Request path is empty.'}
        if(-not $path.StartsWith('/')){$path='/'+$path}
        if($action -eq 'post'){
            $allowedWrite=$path -match '^/wp/v2/(pages|posts)/\d+(\?.*)?$' -or $path -match '^/wp-abilities/v1/abilities/[A-Za-z0-9\-_/]+/run(\?.*)?$' -or $path -match '^/wp/v2/media/\d+(\?.*)?$' -or $path -eq '/rankmath/v1/updateSettings'
            if(-not $allowedWrite){throw "Write path is not allow-listed: $path"}
        }
        $url=$base+$path
        if($action -eq 'post' -and $path -match '^/wp/v2/(pages|posts)/(\d+)'){
            $type=$Matches[1];$id=[int]$Matches[2]
            $readUrl='{0}/wp/v2/{1}/{2}?context=edit' -f $base,$type,$id
            $before=Invoke-Wp -Method 'GET' -Url $readUrl -Headers $headers
            if(-not $before.ok){throw "Preflight read failed HTTP $($before.status): $($before.body)"}
            $beforeObj=$before.body|ConvertFrom-Json;$rawContent=[string]$beforeObj.content.raw;$beforeHash=Get-Sha256 $rawContent
            $expected=if($request.PSObject.Properties.Name -contains 'expected_content_sha256'){[string]$request.expected_content_sha256}else{''}
            if(-not [string]::IsNullOrWhiteSpace($expected) -and $expected.ToLowerInvariant() -ne $beforeHash){throw "Content hash guard failed for $type/$id. Expected $expected, actual $beforeHash"}
            $backupDir='C:\GKBridge\backups';New-Item -ItemType Directory -Force -Path $backupDir|Out-Null;$stamp=Get-Date -Format 'yyyyMMdd-HHmmss';$backupPath=Join-Path $backupDir "$type-$id-$stamp-before.json"
            [IO.File]::WriteAllText($backupPath,$before.body,(New-Object Text.UTF8Encoding($false)))
            $result.backup=$backupPath;$result.preflight=[ordered]@{type=$type;id=$id;content_sha256=$beforeHash;modified=[string]$beforeObj.modified;featured_media=[int]$beforeObj.featured_media}
        }
        $body=$null
        if($action -eq 'post'){if(-not($request.PSObject.Properties.Name -contains 'body')){throw 'POST request requires body.'};$body=$request.body}
        $response=Invoke-Wp -Method $action.ToUpperInvariant() -Url $url -Headers $headers -Body $body;$result.response=$response
        if(-not $response.ok){throw "WordPress request failed HTTP $($response.status): $($response.body)"}
        if($action -eq 'post' -and $path -match '^/wp/v2/(pages|posts)/(\d+)'){
            $type=$Matches[1];$id=[int]$Matches[2];$verifyUrl='{0}/wp/v2/{1}/{2}?context=edit' -f $base,$type,$id;$verify=Invoke-Wp -Method 'GET' -Url $verifyUrl -Headers $headers
            if(-not $verify.ok){throw "Verification read failed HTTP $($verify.status): $($verify.body)"}
            $verifyObj=$verify.body|ConvertFrom-Json
            if($request.body.PSObject.Properties.Name -contains 'content'){$actualRaw=[string]$verifyObj.content.raw;$expectedRaw=[string]$request.body.content;if((Get-Sha256 $actualRaw) -ne (Get-Sha256 $expectedRaw)){throw 'Verification hash mismatch after content write.'};$result.response|Add-Member -NotePropertyName verified_content_sha256 -NotePropertyValue (Get-Sha256 $actualRaw) -Force}
            if($request.body.PSObject.Properties.Name -contains 'featured_media'){if([int]$verifyObj.featured_media -ne [int]$request.body.featured_media){throw "Featured-media verification mismatch: expected $($request.body.featured_media), actual $($verifyObj.featured_media)"};$result.response|Add-Member -NotePropertyName verified_featured_media -NotePropertyValue ([int]$verifyObj.featured_media) -Force}
        }
        $result.success=$true
    }
}
catch{$result.error=$_.Exception.Message}
finally{Write-JsonUtf8NoBom -Path $ResultPath -Value $result}
if(-not $result.success){exit 1}
exit 0
