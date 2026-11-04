param([ValidateSet('cdc','controls','osd','transitions','pcm','scaling','protocol')][string]$Suite='controls')
. "$PSScriptRoot\tool_paths.ps1"
$h=$Hdl;$bin=$ModelSimBin;$py=$PythonExe;$root=$ProjectRoot
function Run-Sim([string]$Dir,[string]$Top,[array]$Sources,[string]$Marker,[array]$Options=@(),[string]$Reject=''){
 New-Item -ItemType Directory -Force -Path $Dir|Out-Null
 if(Test-Path -LiteralPath "$Dir\result.json"){throw "Existing result; select a new run directory: $Dir"}
 $inputs=@($Sources|ForEach-Object{[pscustomobject]@{Path=$_;SHA256=(Get-FileHash -LiteralPath $_).Hash}})
 $inputs|ConvertTo-Json -Depth 5|Set-Content "$Dir\inputs.json"
 Push-Location -LiteralPath $Dir
 try{
  & "$bin\vlib.exe" work *> vlib.log
  & "$bin\vlog.exe" -sv "+incdir+$h" "+incdir+$h\SD" "+incdir+$PSScriptRoot" "+incdir+$root\src\td_project" "+incdir+$root\sim\current\scaling\fixtures" @Sources *> compile.log
  if($LASTEXITCODE){throw "Compile failed: $Dir"}
  & "$bin\vsim.exe" -c -onfinish stop "work.$Top" @Options -do 'run -all;quit -f' *> run.log
  $code=$LASTEXITCODE;$text=Get-Content -LiteralPath run.log -Raw
  $pass=if($Reject){$text.Contains($Reject)-and !$text.Contains($Marker)}else{$code-eq 0-and $text.Contains($Marker)-and $text-notmatch '\*\* (Fatal|Error):'}
  [pscustomobject]@{Passed=$pass;Negative=[bool]$Reject;Top=$Top;Options=$Options;ExitCode=$code;Project=$root;Time=(Get-Date -Format o)}|ConvertTo-Json -Depth 5|Set-Content result.json
  if(!$pass){throw "Simulation failed: $Dir\run.log"}
  Write-Output "PASS $Top $($Options -join ' ')"
 }finally{Pop-Location}
}
switch($Suite){
 'cdc'{& "$PSScriptRoot\run_advanced_tests.ps1" -SkipMain;if($LASTEXITCODE){throw 'CDC failed'}}
 'controls'{& "$PSScriptRoot\current\controls\run_tests.ps1" -Project $root -SkipFixedChain;if($LASTEXITCODE){throw 'Controls failed'}}
 'pcm'{
  & "$PSScriptRoot\current\pcm\run_real_pcm_presentation.ps1" -Project $root -Case submission -ModelSimBin $bin
  & "$PSScriptRoot\current\pcm\run_real_pcm_presentation.ps1" -Project $root -Case submission -Negative -ModelSimBin $bin
 }
 'osd'{
  $d="$PSScriptRoot\current\osd";$out="$d\runs\actual"
  $src=@('image_melody_rom.v','showcase_music_overlay_fast.v','showcase_music_overlay_spectrum.v','dynamic_subtitle_overlay.v','scene_notice.v','showcase_ui_pipeline.v','showcase_presentation_pipeline.v')|ForEach-Object{Join-Path $h $_}
  $src+=@("$d\inputs\ui_frozen.v","$d\inputs\presentation_frozen.v","$d\tb_osd_layout.sv")
  Run-Sim $out tb_osd_layout $src 'OSD_LAYOUT_CAPTURE_PASS' @("+INPUT_ROOT=$($d -replace '\\','/')/inputs")
  & $py -X utf8 "$d\verify_osd_pixels.py" actual
  if($LASTEXITCODE){throw 'OSD mathematical pixel comparison failed'}
 }
 'transitions'{
  $d="$PSScriptRoot\current\transitions"
  foreach($case in 'full','legacy_state','legacy_pixels'){
   $pic=if($case-eq 'full'){"$h\picture_transition.v"}else{"$d\legacy_F879_picture_transition.v"}
   $tb="$d\tb_strict_fade_slide.sv"
   if($case-eq 'legacy_pixels'){
    $line='    if(!expected_slide && effect!=0 && state==2)fail("legacy WIPE selected during required FADE");'
    $t=[IO.File]::ReadAllText($tb);if(!$t.Contains($line)){throw 'Negative checker fixture mismatch'}
    $tb="$d\tb_legacy_pixels.sv";[IO.File]::WriteAllText($tb,$t.Replace($line,'    // Let the legacy mode reach the independent RGB assertion.'))
   }
   $src=@("$h\slide_transition_ctrl.v","$h\video_fade.v",$pic,"$h\image_audio_cdc.v","$h\scene_notice.v",$tb)
   $reject=if($case-eq 'legacy_state'){'STRICT_TRANSITION_REJECT legacy WIPE selected'}elseif($case-eq 'legacy_pixels'){'STRICT_TRANSITION_REJECT actual photo RGB differs'}else{''}
   $opts=if($case-eq 'full'){@('-gFULL=1')}else{@()}
   Run-Sim "$d\$case" tb_strict_fade_slide $src 'STRICT_TRANSITION_PASS' $opts $reject
  }
 }
 'scaling'{
  $d="$PSScriptRoot\current\scaling";$raw="$d\fixtures\all_twelve.raw"
  $src=@("$h\SD\bmp_read.v","$h\bmp_pixel_decoder.v","$h\sd_sector_buffer.v","$h\image_scaler_generic.v","$h\frame_completion_guard.v","$d\tb_large_bmp.v")
  Run-Sim "$d\runs\bmp_fit" tb_large_bmp $src 'GENERIC_BMP_TEST_PASS' @('-gMODE=0',"+RAW=$raw")
  Run-Sim "$d\runs\bmp_negative" tb_large_bmp $src 'GENERIC_BMP_TEST_PASS' @('-gMODE=0',"+RAW=$raw",'+BAD_PIXEL') 'GENERIC_BMP_CHECKER_REJECT scaled pixel mathematical oracle'
  foreach($mode in 0,1,2){Run-Sim "$d\runs\scaler_$mode" tb_generic_scaler @("$h\image_scaler_generic.v","$d\tb_generic_scaler.v") 'GENERIC_SCALER_TEST_PASS' @("-gMODE=$mode")}
  Run-Sim "$d\runs\errors" tb_bmp720_errors @("$h\SD\bmp_read.v","$h\sd_sector_buffer.v","$h\bmp_pixel_decoder.v","$d\tb_generic_errors.v") 'BMP720_ERRORS_TEST_PASS rejected=20' @("+RAW=$root/doc/TF_card/tourism_720p.raw")
 }
 'protocol'{
  $rgb="$PSScriptRoot\current\osd\runs\actual\RTL_OSD_after_f0.rgb"
  if(!(Test-Path -LiteralPath $rgb)){throw 'Run osd first; protocol replays the actual captured RTL frame'}
  & "$PSScriptRoot\current\protocol\run_protocol.ps1" -Project $root -Rgb $rgb -Case submission
 }
}
