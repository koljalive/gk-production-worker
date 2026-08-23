Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$inputPath=Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-editorial-batch.json'
$batch=Get-Content $inputPath -Encoding UTF8 -Raw|ConvertFrom-Json
$items=@()
foreach($x in $batch.items){
  $html=[string]$x.content_raw
  $headings=@([regex]::Matches($html,'(?is)<h([1-6])[^>]*>(.*?)</h\1>')|ForEach-Object{
    [ordered]@{level=[int]$_.Groups[1].Value;text=[Net.WebUtility]::HtmlDecode(([regex]::Replace($_.Groups[2].Value,'<[^>]+>',' '))).Trim()}
  })
  $images=@([regex]::Matches($html,'(?is)<img\b[^>]*>')|ForEach-Object{
    $tag=$_.Value;$src=[regex]::Match($tag,'(?is)\bsrc\s*=\s*["'']([^"'']+)["'']');$alt=[regex]::Match($tag,'(?is)\balt\s*=\s*["'']([^"'']*)["'']')
    [ordered]@{src=if($src.Success){$src.Groups[1].Value}else{''};alt=if($alt.Success){[Net.WebUtility]::HtmlDecode($alt.Groups[1].Value)}else{''}}
  })
  $hrefs=@([regex]::Matches($html,'(?is)<a\b[^>]*\bhref\s*=\s*["'']([^"'']+)["'']')|ForEach-Object{$_.Groups[1].Value})
  $dupes=@($hrefs|Group-Object|Where-Object{$_.Count-gt 1}|Sort-Object Count -Descending|ForEach-Object{[ordered]@{href=$_.Name;count=$_.Count}})
  $plain=[Net.WebUtility]::HtmlDecode([regex]::Replace([regex]::Replace($html,'(?is)<script\b.*?</script>|<style\b.*?</style>',' '),'<[^>]+>',' '))
  $plain=[regex]::Replace($plain,'\s+',' ').Trim()
  $flags=@()
  if($html-match 'gk-premium-article'){$flags+='nested_premium_wrapper'}
  if($html-match 'gk-editorial-article'){$flags+='nested_editorial_wrapper'}
  if($html-match 'gk_visual_object'){$flags+='schematic_visual'}
  if($html-match '\[Expert Upgrade\]|\[Knowledge Upgrade\]'){$flags+='visible_upgrade_label'}
  if($html-match 'Dieser Abschnitt erweitert den Beitrag'){$flags+='generic_filler'}
  if($dupes.Count-gt 0){$flags+='duplicate_links'}
  if($headings.Count -gt 18){$flags+='excessive_headings'}
  $mojibake=([regex]::Matches($plain,'[\u00C2\u00C3\u00E2]')).Count
  if($mojibake-gt 0){$flags+='possible_mojibake'}
  $items+=[ordered]@{
    id=[int]$x.id;type=[string]$x.type;title=[string]$x.title;slug=[string]$x.slug;url=[string]$x.url
    words=[int]$x.words;html_chars=$html.Length;heading_count=$headings.Count;headings=$headings
    image_count=$images.Count;images=$images;duplicate_links=$dupes;flags=$flags;mojibake_hits=$mojibake
    text_start=$plain.Substring(0,[Math]::Min(500,$plain.Length))
  }
}
$out=[ordered]@{generated_utc=(Get-Date).ToUniversalTime().ToString('o');offline_only=$true;production_writes=0;batch_count=$items.Count;items=$items;status='OFFLINE_EDITORIAL_STRUCTURE_AUDITED'}
[IO.File]::WriteAllText((Join-Path $env:GITHUB_WORKSPACE 'bridge/gk-offline-editorial-structure.json'),($out|ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding($false)))
Write-Host "Offline editorial structure audited: $($items.Count), writes=0"