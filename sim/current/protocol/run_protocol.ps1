param([Parameter(Mandatory=$true)][string]$Project,[Parameter(Mandatory=$true)][string]$Rgb,[string]$Case='M5_final')
$ErrorActionPreference='Stop'
$projectPath=(Resolve-Path -LiteralPath $Project).Path
$rgbPath=(Resolve-Path -LiteralPath $Rgb).Path
$h=Join-Path $projectPath 'src\user_source\hdl_source'
$d=Join-Path $PSScriptRoot $Case
if(Test-Path -LiteralPath "$d\inputs.json"){throw 'Use a new Case to preserve prior protocol evidence'}
New-Item -ItemType Directory -Force -Path $d|Out-Null
$bin=if($env:MODELSIM_BIN){$env:MODELSIM_BIN}else{'D:\modelism10.4\win64'}
$py=if($env:PYTHON_EXE){$env:PYTHON_EXE}else{(Get-Command python.exe -ErrorAction Stop).Source}
$core=Join-Path $h 'hdmi1.4b_transmitter_core\hdmi_1_4b_transmitter_core_wrapper.enc.v'
$names=@('video_rgb_to_axis_640x480.v','image_audio_cdc.v','image_melody_i2s.v','I2S_receiver.v','audio_arc_calculate.v')
$sources=@($names|ForEach-Object{Join-Path $h $_})
$vendor=@(Get-ChildItem (Join-Path $(if($env:TD_HOME){$env:TD_HOME}else{'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116'}) 'sim_release\eg4') -Filter '*.v'|ForEach-Object{$_.FullName})
$inputs=@(($sources+$vendor+@($core,"$h\image_melody_pcm.v","$h\image_melody_rom.v","$PSScriptRoot\tb_protocol_720.v",$rgbPath))|ForEach-Object{[pscustomobject]@{Path=$_;SHA256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}})
[pscustomobject]@{Project=$projectPath;RGB=$rgbPath;Sources=$inputs;Boundary='Actual encrypted HDMI core public TMDS, current AXIS/audio/ACR RTL; replays one captured RTL raster. Separate live full-chain test covers video layers. Not LVDS33 eye/board/precise48k signoff.'}|ConvertTo-Json -Depth 6|Set-Content "$d\inputs.json"
Push-Location -LiteralPath $d
try{
 & "$bin\vlib.exe" work *> vlib.log
 & "$bin\vlog.exe" @vendor *> vendor_compile.log
 if($LASTEXITCODE){throw 'Vendor models compile failed'}
 & "$bin\vlog.exe" $core *> core_compile.log
 if($LASTEXITCODE){throw 'Encrypted core compile failed'}
 & "$bin\vlog.exe" -sv "+incdir+$h" @sources "$PSScriptRoot\tb_protocol_720.v" *> compile.log
 if($LASTEXITCODE){throw 'Current protocol RTL compile failed'}
 & "$bin\vsim.exe" -c work.tb_protocol_720 work.glbl "+RGB=$rgbPath" -do 'run -all;quit -f' *> run.log
 $log=Get-Content run.log -Raw
 if(!$log.Contains('AUDIO720_CORE_CAPTURE_PASS') -or $log -match '\*\* (Fatal|Error):'){throw 'Protocol capture failed'}
 & $py -X utf8 "$PSScriptRoot\check_current.py" --folder $d --rgb $rgbPath *> checker.log
 if($LASTEXITCODE){throw 'Independent video/audio protocol checker failed'}
 Write-Output "PASS current encrypted HDMI video/audio protocol $Case"
}finally{Pop-Location}
