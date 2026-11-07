# 只修改游戏 audio/ 中的 WAV；.import 由 Godot 编辑器自动维护。
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$game = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$audio = Join-Path $game 'audio'
$backups = Join-Path (Split-Path (Split-Path $game -Parent) -Parent) '.codex-drafts/audio-backups'
$slots = [ordered]@{
    '打击音'='hit.wav'; '按钮点击'='click.wav'; '剧情信息'='info.wav'
    '进入曲目'='enter_the_song.wav'; '进入最终曲'='enter_the_final.wav'
    '警告提示'='warning.wav'; '校准轻拍'='offest1.wav'; '校准重拍'='offest2.wav'
}
$sources = @{}; $gains = @{}; $preview = $null
function Find-Tool([string]$name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $preferred = "D:\Workspaces\FFmpeg\ffmpeg\bin\$name.exe"
    if (Test-Path -LiteralPath $preferred) { return $preferred }
    return $null
}
$ffmpeg = Find-Tool 'ffmpeg'; $ffplay = Find-Tool 'ffplay'
function Error-Box([string]$message) { [Windows.Forms.MessageBox]::Show($message,'音效替换工具','OK','Error') | Out-Null }
function Slot { [string]$slotBox.SelectedItem }
function Target { Join-Path $audio $slots[(Slot)] }
function Gain { [double]$gainBar.Value / 10.0 }
function Stop-Preview {
    if ($preview -and -not $preview.HasExited) { try { $preview.Kill() } catch {} }
    $script:preview = $null
}
function Start-Tool([string]$exe,[string[]]$argumentList,[bool]$capture) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $exe; $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $capture; $info.RedirectStandardError = $capture
    foreach ($arg in $argumentList) { [void]$info.ArgumentList.Add($arg) }
    [Diagnostics.Process]::Start($info)
}
function Play-File([string]$path,[double]$gain) {
    if (-not $ffplay) { Error-Box '找不到 FFplay，请把 FFmpeg 的 bin 目录加入 PATH。'; return }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Error-Box "找不到文件：$path"; return }
    Stop-Preview
    try {
        $filter = 'volume={0:F1}dB' -f $gain
        $script:preview = Start-Tool $ffplay @('-nodisp','-autoexit','-loglevel','error','-af',$filter,$path) $false
        $status.Text = ('正在试听：{0}（{1:+0.0;-0.0;0.0} dB）' -f [IO.Path]::GetFileName($path),$gain)
    } catch { Error-Box "试听失败：$($_.Exception.Message)" }
}
function Add-Label([string]$text,[int]$x,[int]$y,[int]$width) {
    $c = [Windows.Forms.Label]::new(); $c.Text=$text
    $c.Location=[Drawing.Point]::new($x,$y); $c.Size=[Drawing.Size]::new($width,28)
    $c.AutoEllipsis=$true; $form.Controls.Add($c); return $c
}
function Add-Button([string]$text,[int]$x,[int]$y,[int]$width) {
    $c = [Windows.Forms.Button]::new(); $c.Text=$text
    $c.Location=[Drawing.Point]::new($x,$y); $c.Size=[Drawing.Size]::new($width,34)
    $form.Controls.Add($c); return $c
}

$form=[Windows.Forms.Form]::new(); $form.Text='Univerthm 音效替换'
$form.ClientSize=[Drawing.Size]::new(690,365); $form.StartPosition='CenterScreen'
$form.Font=[Drawing.Font]::new('Microsoft YaHei UI',10)
$form.FormBorderStyle='FixedSingle'; $form.MaximizeBox=$false
$null=Add-Label '音效位置' 20 22 95
$slotBox=[Windows.Forms.ComboBox]::new(); $slotBox.Location=[Drawing.Point]::new(120,19)
$slotBox.Size=[Drawing.Size]::new(230,30); $slotBox.DropDownStyle='DropDownList'
foreach ($key in $slots.Keys) { [void]$slotBox.Items.Add($key) }; $form.Controls.Add($slotBox)
$null=Add-Label '游戏里的文件' 20 69 95; $targetName=Add-Label '' 120 69 540
$null=Add-Label '候选音效' 20 110 95; $sourceName=Add-Label '尚未选择候选 WAV' 120 110 400
$pick=Add-Button '挑选 WAV…' 535 102 135
$null=Add-Label '试听音量' 20 160 95
$gainBar=[Windows.Forms.TrackBar]::new(); $gainBar.Location=[Drawing.Point]::new(120,146)
$gainBar.Size=[Drawing.Size]::new(445,48); $gainBar.Minimum=-300; $gainBar.Maximum=60
$gainBar.TickFrequency=50; $gainBar.SmallChange=5; $gainBar.LargeChange=10
$form.Controls.Add($gainBar); $gainText=Add-Label '0.0 dB' 575 160 90
$play=Add-Button '试听候选' 120 205 110; $current=Add-Button '试听当前' 240 205 110
$stop=Add-Button '停止' 360 205 80; $apply=Add-Button '应用到游戏（自动备份）' 120 254 265
$null=Add-Label '调节会写入新 WAV；0 dB 保持原音量。替换后回到 Godot 等待重新导入。' 20 305 650
$status=Add-Label '先选位置，再挑一个 WAV 试听。' 20 327 650
$status.Font=[Drawing.Font]::new('Microsoft YaHei UI',9)

$slotBox.add_SelectedIndexChanged({
    Stop-Preview; $key=Slot; $targetName.Text=$slots[$key]
    $sourceName.Text=if ($sources.ContainsKey($key)) {$sources[$key]} else {'尚未选择候选 WAV'}
    $gainBar.Value=if ($gains.ContainsKey($key)) {[int]$gains[$key]} else {0}
})
$gainBar.add_ValueChanged({
    $gains[(Slot)]=$gainBar.Value
    $gainText.Text=('{0:+0.0;-0.0;0.0} dB' -f (Gain))
})
$pick.add_Click({
    $dialog=[Windows.Forms.OpenFileDialog]::new()
    $dialog.Title='选择 WAV 音效'; $dialog.Filter='WAV 音频 (*.wav)|*.wav'
    if ($dialog.ShowDialog($form) -eq 'OK') {
        $sources[(Slot)]=$dialog.FileName; $sourceName.Text=$dialog.FileName
        $status.Text='已选择候选音效，可以试听。'
    }
    $dialog.Dispose()
})
$play.add_Click({
    $key=Slot
    if (-not $sources.ContainsKey($key)) {Error-Box '先点「挑选 WAV…」。'; return}
    Play-File $sources[$key] (Gain)
})
$current.add_Click({Play-File (Target) 0.0})
$stop.add_Click({Stop-Preview})
$apply.add_Click({
    $key=Slot
    if (-not $sources.ContainsKey($key)) {Error-Box '先点「挑选 WAV…」。'; return}
    if (-not $ffmpeg) {Error-Box '找不到 FFmpeg，请把 FFmpeg 的 bin 目录加入 PATH。'; return}
    $source=$sources[$key]; $target=Target
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {Error-Box "找不到候选文件：$source"; return}
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {Error-Box "找不到游戏音效：$target"; return}
    if ((Gain) -gt 0) {
        $answer=[Windows.Forms.MessageBox]::Show('提高音量可能导致失真。继续应用？','可能削波','YesNo','Warning')
        if ($answer -ne 'Yes') {return}
    }
    Stop-Preview; $temp=$null
    try {
        [void][IO.Directory]::CreateDirectory($backups)
        $temp=Join-Path $backups ([Guid]::NewGuid().ToString('N')+'.wav')
        $filter='volume={0:F1}dB' -f (Gain)
        $process=Start-Tool $ffmpeg @('-hide_banner','-loglevel','error','-y','-i',$source,'-map','0:a:0','-af',$filter,'-c:a','pcm_s16le',$temp) $true
        if (-not $process.WaitForExit(120000)) {$process.Kill(); throw '转换超过两分钟。'}
        $errorText=$process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $temp) -or (Get-Item -LiteralPath $temp).Length -lt 44) {
            throw "FFmpeg 转换失败：$errorText"
        }
        $stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'
        $backup=Join-Path $backups (([IO.Path]::GetFileNameWithoutExtension($target))+"-$stamp.wav")
        [IO.File]::Copy($target,$backup,$false)
        [IO.File]::Move($temp,$target,$true); $temp=$null
        $status.Text="已替换 $([IO.Path]::GetFileName($target))；原文件备份：$backup"
        [Windows.Forms.MessageBox]::Show("替换成功。`n原文件备份：$backup`n`n请回到 Godot 等待重新导入。",'完成','OK','Information') | Out-Null
    } catch {Error-Box "替换失败：$($_.Exception.Message)"}
    finally {if ($temp -and (Test-Path -LiteralPath $temp)) {Remove-Item -LiteralPath $temp -Force}}
})
$form.add_FormClosing({Stop-Preview}); $slotBox.SelectedIndex=0
if (-not $ffmpeg -or -not $ffplay) {$form.add_Shown({Error-Box '找不到 FFmpeg 或 FFplay。请把 FFmpeg 的 bin 目录加入 PATH。'})}
[Windows.Forms.Application]::Run($form)
