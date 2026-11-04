param([Parameter(Mandatory=$true)][string]$Project,[switch]$SkipFixedChain)
$ErrorActionPreference='Stop'
$projectPath=(Resolve-Path -LiteralPath $Project).Path
$h=Join-Path $projectPath 'src\user_source\hdl_source'
$bin=if($env:MODELSIM_BIN){$env:MODELSIM_BIN}else{'D:\modelism10.4\win64'}
$tag=(Split-Path $projectPath -Leaf)-replace '[^A-Za-z0-9_.-]','_'
$build=Join-Path $PSScriptRoot "runs\$tag"
New-Item -ItemType Directory -Path $build -Force|Out-Null
$results=@()
function Run-One([string]$Name,[string]$Top,[array]$Sources,[string]$Marker,[string]$Reject,[array]$Options,[bool]$Negative){
 $d=Join-Path $build $Name
 New-Item -ItemType Directory -Path $d -Force|Out-Null
 if(Test-Path -LiteralPath "$d\run.log"){
  $a=Join-Path $d ('attempt_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
  New-Item -ItemType Directory -Path $a -Force|Out-Null
  Get-ChildItem -LiteralPath $d -File|Where-Object{$_.Extension -in '.log','.json'}|Copy-Item -Destination $a
 }
 $inputs=@($Sources|ForEach-Object{[pscustomobject]@{Path=$_;SHA256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}})
 [pscustomobject]@{Project=$projectPath;Sources=$inputs;Parameters=$Options;Boundary='Component digital RTL only; not integrated top, routed retention, metastability or hardware signoff'}|ConvertTo-Json -Depth 8|Set-Content "$d\inputs.json"
 Push-Location $d
 try{
  & "$bin\vlib.exe" work *> vlib.log
  & "$bin\vlog.exe" -sv @Sources *> compile.log
  if($LASTEXITCODE){throw "Compile failed: $d"}
  & "$bin\vsim.exe" -c "work.$Top" @Options -do 'run -all;quit -f' *> run.log
  $text=Get-Content -LiteralPath run.log -Raw
  $pass=if($Negative){$text.Contains($Reject)-and !$text.Contains($Marker)}else{$text.Contains($Marker)-and $text -notmatch '\*\* (Fatal|Error):'}
  $entry=[pscustomobject]@{Name=$Name;Passed=$pass;Negative=$Negative;Project=$projectPath;Time=(Get-Date -Format o);HardwareTested=$false}
  $entry|ConvertTo-Json|Set-Content result.json
  $script:results+=$entry
  Write-Output "$(if($pass){'PASS'}else{'FAIL'}) $Name"
  if(!$pass){throw "Checker failed: $d"}
 }finally{Pop-Location}
}
$keys=@("$h\adjustment_key_control.v","$PSScriptRoot\tb_adjust_keys_v2.v")
Run-One 'keys' 'tb_adjust_keys_v2' $keys 'ADJUST_KEYS_V2_TEST_PASS' '' @() $false
foreach($fault in 'KEY','CHORD'){
 Run-One "keys_negative_$fault" 'tb_adjust_keys_v2' $keys 'ADJUST_KEYS_V2_TEST_PASS' 'ADJUST_KEYS_CHECKER_REJECT' @("+FAULT_$fault") $true
}
$math=@("$h\video_adjust_percent.v","$PSScriptRoot\tb_adjust_percent.v")
Run-One 'math_all_parameters' 'tb_adjust_percent' $math 'ADJUST_PERCENT_TEST_PASS' '' @() $false
Run-One 'math_negative' 'tb_adjust_percent' $math 'ADJUST_PERCENT_TEST_PASS' 'ADJUST_PERCENT_CHECKER_REJECT' @('+FAULT') $true
$interval=@("$h\playback_interval_control.v","$h\SD\sd_card_bmp.v","$PSScriptRoot\tb_playback_interval.v")
Run-One 'interval_3_5_10' 'tb_playback_interval' $interval 'PLAYBACK_INTERVAL_TEST_PASS' '' @() $false
Run-One 'interval_negative' 'tb_playback_interval' $interval 'PLAYBACK_INTERVAL_TEST_PASS' 'INTERACTION_CHECKER_REJECT' @('+INJECT_INTERVAL') $true
$bridge=@('SD\sd_card_bmp.v','playback_interval_control.v','presentation_control.v','adjustment_key_control.v','scaling_metadata_format.v','compliance_control_bridge.v','osd_status_cdc.v')|ForEach-Object{Join-Path $h $_}
$bridge+=Join-Path $PSScriptRoot 'tb_compliance_control.v'
foreach($phase in 0,2,5,9){Run-One "mailbox_phase_$phase" 'tb_compliance_control' $bridge 'COMPLIANCE_CONTROL_TEST_PASS' '' @("-gPHASE=$phase") $false}
Run-One 'mailbox_negative_TORN' 'tb_compliance_control' $bridge 'COMPLIANCE_CONTROL_TEST_PASS' 'COMPLIANCE_CONTROL_CHECKER_REJECT' @('+TORN') $true
if(!$SkipFixedChain){
 $top=Get-Content -LiteralPath "$h\top_tf_hdmi_audio.v" -Raw
 $assign='assign vout_data_adjusted_raw = adjusted_actual_rgb;'
 if(!$top.Contains($assign)){throw 'Fixed-chain test requires actual prepared M2 top selector'}
 if(!$top.Contains('.rgb(osd_rgb),.phase(2''d0),')){throw 'M2 top label must describe fixed A path'}
 $selector='module m2_selector_from_project(input[23:0] adjusted_actual_rgb,diagnostic_bypass_rgb,input[1:0]diagnostic_phase,output[23:0]vout_data_adjusted_raw);'+"`n"+$assign+"`n"+'initial if($test$plusargs("SELECT"))force vout_data_adjusted_raw=diagnostic_phase[0]?diagnostic_bypass_rgb:adjusted_actual_rgb; endmodule'
 $selectorPath=Join-Path $build 'm2_selector_from_project.v'
 $selector|Set-Content -LiteralPath $selectorPath
 $chain=@('video_adjust_percent.v','pixel_identity_delay.v','diagnostic_frame_phase.v','hdmi_diagnostic_overlay.v')|ForEach-Object{Join-Path $h $_}
 $chain+=@($selectorPath,(Join-Path $PSScriptRoot 'tb_m2_fixed_adjust.v'))
 Run-One 'fixed_adjust_chain' 'tb_m2_fixed_adjust' $chain 'M2_FIXED_TEST_PASS' '' @() $false
 foreach($fault in 'SELECT','ALIGN'){
  Run-One "fixed_negative_$fault" 'tb_m2_fixed_adjust' $chain 'M2_FIXED_TEST_PASS' 'M2_FIXED_CHECKER_REJECT' @("+$fault") $true
 }
}
$results|ConvertTo-Json -Depth 8|Set-Content (Join-Path $build 'results.json')
