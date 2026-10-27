<#
.SYNOPSIS
  把谱面包里的解锁视频烘焙成「帧序列 + 音频」，写回同一个 zip，供 Godot 播放。

.DESCRIPTION
  为什么不用 ogv：本机装的 ffmpeg（4.1 / 2018 构建）编码 libtheora 是坏的
  （theora_encode_packetout failed / 解出来是噪点），Godot 只认 Theora，所以改走帧序列：
    unlock_frames/00001.jpg ...  （默认 15fps，宽 1280）
    unlock_audio.ogg            （OggVorbis，Godot 的 AudioStreamOggVorbis 能直接放）
    unlock.json                 （fps / 帧数 / 时长 / 音频文件名）

  Godot 侧只要按时间翻帧 + 放音频即可，不依赖视频解码。

.PARAMETER ZipPath
  谱面包路径。不填就取 Godot 用户目录里最新的 zip。

.PARAMETER Fps
  抽帧帧率，默认 15。

.PARAMETER Width
  帧宽，默认 1280（高度按比例）。

.PARAMETER Watch
  守着 charts 目录，发现「有视频但还没烘焙」的 zip 就自动处理。
#>
param(
  [string]$ZipPath = "",
  [int]$Fps = 15,
  [int]$Width = 1280,
  [switch]$Watch
)

$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ChartsDir = Join-Path $env:APPDATA "Godot\app_userdata\Rhythm Game\charts"

function Find-Ffmpeg {
  $candidates = @()
  if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA "RhythmTools\ffmpeg\bin\ffmpeg.exe") }
  $candidates += "C:\ffmpeg\bin\ffmpeg.exe"
  $candidates += "C:\Program Files\ffmpeg\bin\ffmpeg.exe"
  foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
  $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return ""
}

$Ffmpeg = Find-Ffmpeg
if ($Ffmpeg -eq "") {
  throw "没找到 ffmpeg。装一个：winget install Gyan.FFmpeg（或放到 %LOCALAPPDATA%\RhythmTools\ffmpeg\bin\）"
}
Write-Host "ffmpeg: $Ffmpeg"

function Bake-Zip {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $false }

  $z = [System.IO.Compression.ZipFile]::OpenRead($Path)
  $names = @($z.Entries | ForEach-Object { $_.FullName })
  $hasFrames = @($names | Where-Object { $_ -match '^unlock_frames/.*\.jpg$' }).Count -gt 0
  $videoEntry = $z.Entries | Where-Object { $_.Name -match '\.(mp4|webm|mov|m4v)$' } |
    Sort-Object { $_.Name -match 'unlock|intro|opening' } -Descending | Select-Object -First 1

  if (-not $videoEntry -and -not $hasFrames) { $z.Dispose(); return $false }
  if ($hasFrames) {
    Write-Host "  已有帧序列，跳过: $(Split-Path $Path -Leaf)"
    $z.Dispose(); return $false
  }

  $work = Join-Path $env:TEMP ("bake_" + [guid]::NewGuid().ToString("N"))
  $frameDir = Join-Path $work "frames"
  New-Item -ItemType Directory -Path $frameDir -Force | Out-Null

  $src = Join-Path $work $videoEntry.Name
  [System.IO.Compression.ZipFileExtensions]::ExtractToFile($videoEntry, $src, $true)

  # 时长（从 ffmpeg 输出里抠 Duration）
  $info = @(& $Ffmpeg -hide_banner -i $src 2>&1 | Out-String | Select-String -Pattern 'Duration: (\d+):(\d+):(\d+\.\d+)')
  $duration = 0.0
  if ($info) {
    $m = [regex]::Match($info[0].ToString(), 'Duration: (\d+):(\d+):(\d+\.\d+)')
    if ($m.Success) {
      $duration = [int]$m.Groups[1].Value * 3600 + [int]$m.Groups[2].Value * 60 + [double]$m.Groups[3].Value
    }
  }
  $z.Dispose()

  Write-Host ("  烘焙: " + $videoEntry.Name + "  " + [math]::Round((Get-Item $src).Length / 1MB, 1) + " MB, " + [math]::Round($duration, 2) + "s")

  $sw = [Diagnostics.Stopwatch]::StartNew()
  & $Ffmpeg -y -hide_banner -loglevel error -i $src -vf ("fps=" + $Fps + ",scale=" + $Width + ":-2") -q:v 4 (Join-Path $frameDir "%05d.jpg")
  $frames = @(Get-ChildItem $frameDir -Filter *.jpg)
  if ($frames.Count -eq 0) {
    Write-Warning "  抽帧失败"
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    return $false
  }

  # 音频（没有音轨就跳过）
  $audioPath = Join-Path $work "unlock_audio.ogg"
  & $Ffmpeg -y -hide_banner -loglevel error -i $src -vn -c:a libvorbis -q:a 4 $audioPath
  if (-not (Test-Path $audioPath) -or (Get-Item $audioPath).Length -lt 1024) {
    $audioPath = $null
  }

  $meta = [ordered]@{
    fps     = $Fps
    frames  = $frames.Count
    width   = $Width
    duration = [math]::Round($duration, 3)
    audio   = if ($audioPath) { "unlock_audio.ogg" } else { "" }
    source  = $videoEntry.Name
  }
  $metaPath = Join-Path $work "unlock.json"
  ($meta | ConvertTo-Json) | Set-Content -Path $metaPath -Encoding UTF8

  $totalMB = [math]::Round((($frames | Measure-Object Length -Sum).Sum) / 1MB, 1)
  Write-Host ("  抽到 " + $frames.Count + " 帧（" + $totalMB + " MB），音频 " + $(if ($audioPath) { [math]::Round((Get-Item $audioPath).Length / 1KB, 0).ToString() + " KB" } else { "无" }) + "，用时 " + [math]::Round($sw.Elapsed.TotalSeconds, 1) + "s")

  # 写回 zip：先删旧的 ogv / 帧目录，再写新的
  $upd = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Update)
  $stale = @($upd.Entries | Where-Object { $_.FullName -match '\.ogv$' -or $_.FullName -match '^unlock_frames/' -or $_.FullName -eq 'unlock.json' -or $_.FullName -eq 'unlock_audio.ogg' })
  foreach ($e in $stale) { $e.Delete() }
  foreach ($f in $frames) {
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($upd, $f.FullName, ("unlock_frames/" + $f.Name)) | Out-Null
  }
  if ($audioPath) {
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($upd, $audioPath, "unlock_audio.ogg") | Out-Null
  }
  [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($upd, $metaPath, "unlock.json") | Out-Null
  $upd.Dispose()

  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "  已写入: $(Split-Path $Path -Leaf)"
  return $true
}

if ($Watch) {
  Write-Host ("守着 " + $ChartsDir + " (每 5 秒扫一次, Ctrl+C 退出)")
  while ($true) {
    $zips = @()
    if (Test-Path $ChartsDir) {
      $zips = @(Get-ChildItem $ChartsDir -Filter *.zip | Sort-Object LastWriteTime -Descending | Select-Object -First 3)
    }
    foreach ($z in $zips) {
      try { Bake-Zip -Path $z.FullName | Out-Null } catch { Write-Warning $_.Exception.Message }
    }
    Start-Sleep -Seconds 5
  }
  return
}

if ($ZipPath -eq "") {
  if (-not (Test-Path $ChartsDir)) { throw ("找不到谱面目录: " + $ChartsDir) }
  $z = Get-ChildItem $ChartsDir -Filter *.zip | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $z) { throw ("目录里没有 zip: " + $ChartsDir) }
  $ZipPath = $z.FullName
}
Write-Host "谱面包: $ZipPath"
$done = Bake-Zip -Path $ZipPath
if ($done) { Write-Host "OK" } else { Write-Host "没有需要烘焙的视频（或已经烘焙过）" }
