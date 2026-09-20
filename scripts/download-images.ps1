# One-time download of Play Store images (icon + first 4 screenshots per game)
# into assets/games/<packageId>/, plus assets/games/manifest.json for the site's
# local-image fallback. Plain Windows PowerShell 5.1, no external modules.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent $PSScriptRoot
$htmlPath = Join-Path $repoRoot 'index.html'
$outRoot  = Join-Path $repoRoot 'assets\games'
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

$html = [System.IO.File]::ReadAllText($htmlPath)

function Resize-GU([string]$u) {
  $i = $u.IndexOf('=')
  if ($i -ge 0) { return $u.Substring(0, $i) + '=w800-rw' }
  return $u
}

function Save-Image([string]$url, [string]$dest) {
  if ((Test-Path $dest) -and ((Get-Item $dest).Length -gt 500)) { return $true }
  foreach ($attempt in 1..2) {
    try {
      Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 25 -Headers @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'
      } | Out-Null
      if ((Test-Path $dest) -and ((Get-Item $dest).Length -gt 500)) { return $true }
    } catch { }
    Start-Sleep -Milliseconds 400
  }
  if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
  return $false
}

$entryRx  = [regex]'url:\s*"https://play\.google\.com/store/apps/details\?id=([^"]+)"[\s\S]*?icon:\s*"([^"]+)"[\s\S]*?shots:\s*\[([^\]]*)\]'
$missing  = New-Object System.Collections.Generic.List[string]
$manifest = [ordered]@{}
$sw       = [Diagnostics.Stopwatch]::StartNew()
$count    = 0

foreach ($m in $entryRx.Matches($html)) {
  $count++
  $pkg      = $m.Groups[1].Value
  $icon     = $m.Groups[2].Value
  $shotUrls = @([regex]::Matches($m.Groups[3].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }) | Select-Object -First 4

  $dir   = Join-Path $outRoot $pkg
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $entry = [ordered]@{ icon = $null; shots = @() }

  if ($sw.Elapsed.TotalMinutes -gt 9) {
    $missing.Add("$pkg :: icon (skipped: time cap)")
    for ($i = 0; $i -lt $shotUrls.Count; $i++) { $missing.Add("$pkg :: ss$($i+1).webp (skipped: time cap)") }
    $manifest[$pkg] = $entry
    continue
  }

  if (Save-Image (Resize-GU $icon) (Join-Path $dir 'icon.webp')) {
    $entry.icon = "assets/games/$pkg/icon.webp"
  } else {
    $missing.Add("$pkg :: icon")
  }

  for ($i = 0; $i -lt $shotUrls.Count; $i++) {
    $name = 'ss' + ($i + 1) + '.webp'
    if (Save-Image (Resize-GU $shotUrls[$i]) (Join-Path $dir $name)) {
      $entry.shots += "assets/games/$pkg/$name"
    } else {
      $missing.Add("$pkg :: $name")
    }
  }

  $manifest[$pkg] = $entry
  Write-Host ("{0,2}: {1}  icon={2} shots={3}/{4}" -f $count, $pkg, [bool]$entry.icon, $entry.shots.Count, $shotUrls.Count)
}

$manifestPath = Join-Path $outRoot 'manifest.json'
($manifest | ConvertTo-Json -Depth 5) | Out-File -FilePath $manifestPath -Encoding ascii

Write-Host ''
Write-Host "Games processed : $count"
Write-Host "Manifest        : $manifestPath"
Write-Host "Elapsed         : $([math]::Round($sw.Elapsed.TotalSeconds,1))s"
Write-Host "Missing images  : $($missing.Count)"
foreach ($x in $missing) { Write-Host "  MISSING: $x" }
