param([Parameter(Mandatory=$true)][string]$Project,[string]$Case='current',[switch]$Negative,[string]$ModelSimBin='D:\modelism10.4\win64')
$ErrorActionPreference='Stop'
$taskProject=(Resolve-Path -LiteralPath $Project).Path
$taskHdl=Join-Path $taskProject 'src\user_source\hdl_source'
$taskOutput=Join-Path $PSScriptRoot ('presentation_runs\'+$Case+$(if($Negative){'_ZERO_BANDS'}else{'_normal'}))
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
$taskNames=@('image_melody_i2s.v','image_audio_cdc.v','melody_status_cdc.v','I2S_receiver.v','audio_wave_capture.v','pcm_spectrum_dft512.v','spectrum_snapshot_cdc.v',
 'scene_notice.v','showcase_music_overlay_spectrum.v','showcase_music_overlay_fast.v','dynamic_subtitle_overlay.v','showcase_ui_pipeline.v','showcase_presentation_pipeline.v',
 'fixed_chinese_layout.v','fixed_chinese_row_rom.v','hdmi_diagnostic_overlay.v')
$taskSources=@($taskNames | ForEach-Object {Join-Path $taskHdl $_})+(Join-Path $PSScriptRoot 'tb_real_pcm_presentation.sv')
$taskExtra=@('pcm_spectrum_tables.vh','fixed_chinese_text_decode.vh','fixed_chinese16_init.vh','image_melody_pcm.v','image_melody_rom.v','subtitle_font_rom.v','subtitle_text_rom.v') | ForEach-Object {Join-Path $taskHdl $_}
[pscustomobject]@{Project=$taskProject;Negative=[bool]$Negative;Scope='Actual I2S PCM -> analysis -> mailbox -> enabled production presentation -> Chinese terminal; declared constant test background, no screenshot claim';Sources=@(($taskSources+$taskExtra)|ForEach-Object{[pscustomobject]@{Path=$_;SHA256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}})} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $taskOutput 'inputs.json')
Push-Location -LiteralPath $taskOutput
try {
 if(-not(Test-Path -LiteralPath work)){& (Join-Path $ModelSimBin 'vlib.exe') work *> vlib.log}
 & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$taskHdl" @taskSources *> compile.log
 if($LASTEXITCODE){throw 'M5 PCM production presentation compile failed'}
 $taskArguments=@('-c','-onfinish','stop','work.tb_real_pcm_presentation');if($Negative){$taskArguments+='+ZERO_BANDS'}
 & (Join-Path $ModelSimBin 'vsim.exe') @taskArguments -do 'run -all; quit -f' *> run.log
 $taskText=Get-Content -Raw -LiteralPath run.log
 $taskPassed=if($Negative){$taskText.Contains('M5_PCM_PRESENTATION_REJECT independent real spectrum pixel') -and -not $taskText.Contains('M5_REAL_PCM_PRESENTATION_PASS')}else{$taskText.Contains('M5_REAL_PCM_PRESENTATION_PASS') -and $taskText -notmatch '\*\* (Fatal|Error):'}
 [pscustomobject]@{Passed=$taskPassed;Project=$taskProject;Negative=[bool]$Negative;Time=(Get-Date -Format o)} | ConvertTo-Json | Set-Content -LiteralPath result.json
 if(-not $taskPassed){throw "M5 PCM presentation failed: $taskOutput\run.log"}
 Write-Output "PASS M5 actual PCM production presentation Negative=$Negative Project=$taskProject"
} finally {Pop-Location}
