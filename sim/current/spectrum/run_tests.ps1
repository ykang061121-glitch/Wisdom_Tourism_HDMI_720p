$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\..\tool_paths.ps1"
$h=$Hdl;$bin=$ModelSimBin;$py=$PythonExe
New-Item -ItemType Directory -Force -Path "$PSScriptRoot\logs"|Out-Null
Push-Location -LiteralPath $PSScriptRoot
try{
 if(Test-Path -LiteralPath 'work'){throw 'Preserve previous run; use a clean extracted project for another run'}
 & "$bin\vlib.exe" work *> logs/vlib.log
 function Assert-Run([string]$Name,[string]$Top,[string]$Marker,[array]$Extra=@()){
  & "$bin\vsim.exe" -c "work.$Top" @Extra -do 'run -all;quit -f' *> "logs/$Name.log"
  $t=Get-Content -LiteralPath "logs/$Name.log" -Raw
  if($LASTEXITCODE -or !$t.Contains($Marker) -or $t-match '\*\* (Error|Fatal):'){throw "$Name failed"}
 }
 & "$bin\vlog.exe" "+incdir+$h" "$h\image_melody_pcm.v" tb_capture_real_dds.v *> logs/dds_compile.log
 if($LASTEXITCODE){throw 'DDS compile failed'}
 Assert-Run dds tb_capture_real_dds 'PASS real original DDS PCM capture'
 & $py -X utf8 reference.py prepare *> logs/reference_prepare.log
 if($LASTEXITCODE){throw 'Independent reference generation failed'}
 & "$bin\vlog.exe" -sv "+incdir+$h" "$h\pcm_spectrum_dft512.v" tb_spectrum.v tb_streaming.v *> logs/spectrum_compile.log
 if($LASTEXITCODE){throw 'DFT compile failed'}
 $cases=Get-Content -LiteralPath case_count.txt
 Assert-Run spectrum tb_spectrum 'PASS spectrum snapshots, pause/reset/overrun' @("+CASES=$cases")
 Assert-Run streaming tb_streaming 'PASS continuous 3 hops'
 & $py -X utf8 reference.py check *> logs/reference_check.log
 if($LASTEXITCODE){throw 'Independent DFT comparison failed'}
 & "$bin\vlog.exe" -sv "+incdir+$h" "$h\image_melody_i2s.v" "$h\I2S_receiver.v" tb_actual_pcm_chain.v *> logs/actual_chain_compile.log
 if($LASTEXITCODE){throw 'Actual I2S chain compile failed'}
 Assert-Run actual_chain tb_actual_pcm_chain 'PASS actual PCM chain:'
 & $py -X utf8 check_actual_chain.py *> logs/actual_chain_check.log
 if($LASTEXITCODE){throw 'Actual I2S PCM reference failed'}
 [pscustomobject]@{Passed=$true;Algorithm='512-point direct DFT, periodic Hann, 16 bands';Cases=[int]$cases;ActualI2SSnapshots=24;Source=(Get-FileHash -LiteralPath "$h\pcm_spectrum_dft512.v").Hash;Time=(Get-Date -Format o)}|ConvertTo-Json|Set-Content result.json
 Write-Output 'PASS independent DFT mathematics, four original melodies, actual I2S input and streaming'
}finally{Pop-Location}
