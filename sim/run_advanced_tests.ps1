param([switch]$SkipMain)
$ErrorActionPreference='Stop'
if(!$SkipMain){
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\run_tests.ps1"
    if($LASTEXITCODE){exit $LASTEXITCODE}
}
# Preserve the original reliability fixture and every assertion. This wrapper
# avoids its legacy string-pipeline Get-FileHash metadata bug on PowerShell5.
$root=Split-Path -Parent $PSScriptRoot
$hdl=Join-Path $root 'src\user_source\hdl_source'
$build=Join-Path $PSScriptRoot 'build\advanced_cdc'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$tool=Get-Command vsim.exe -ErrorAction SilentlyContinue
$bin=if($env:MODELSIM_BIN){$env:MODELSIM_BIN}elseif($tool){Split-Path -Parent $tool.Source}else{'D:\modelism10.4\win64'}
$sources=@('osd_status_cdc.v','melody_status_cdc.v','image_audio_cdc.v','frame_completion_guard.v','fade_transition_cdc.v','fade_transition_ctrl.v') | ForEach-Object {Join-Path $hdl $_}
$results=@();Push-Location $build
try{
    & "$bin\vlib.exe" work *> vlib.log
    & "$bin\vlog.exe" -sv @sources "$PSScriptRoot\tb_reliability_cdc.v" *> compile.log
    if($LASTEXITCODE){throw 'CDC compile failed'}
    foreach($phase in 0,7,19,39){
        & "$bin\vsim.exe" -c work.tb_reliability_cdc "+PHASE=$phase" -do 'run -all; quit -f' *> "phase_$phase.log"
        $text=Get-Content -LiteralPath "phase_$phase.log" -Raw
        $pass=$text.Contains('RELIABILITY_CDC_TEST_PASS') -and $text -notmatch '\*\* (Fatal|Error):'
        $results += [pscustomobject]@{Name="CDC phase $phase";Passed=$pass}
        Write-Host "$(if($pass){'PASS'}else{'FAIL'}) CDC phase $phase"
    }
    foreach($fault in 'TORN_CDC','EARLY_READY'){
        & "$bin\vsim.exe" -c work.tb_reliability_cdc "+INJECT_$fault" -do 'run -all; quit -f' *> "negative_$fault.log"
        $text=Get-Content -LiteralPath "negative_$fault.log" -Raw
        $pass=$text.Contains('RELIABILITY_CHECKER_REJECT') -and !$text.Contains('RELIABILITY_CDC_TEST_PASS')
        $results += [pscustomobject]@{Name="negative CDC $fault";Passed=$pass}
        Write-Host "$(if($pass){'PASS'}else{'FAIL'}) negative CDC $fault"
    }
    $hashes=@(($sources+"$PSScriptRoot\tb_reliability_cdc.v") | ForEach-Object {Get-FileHash -LiteralPath $_})
    [pscustomobject]@{RecordedAt=(Get-Date -Format o);Results=$results;SourceHashes=$hashes} |
        ConvertTo-Json -Depth 6 | Out-File -LiteralPath summary.json -Encoding utf8
    if(@($results | Where-Object {!$_.Passed}).Count){exit 1}
    exit 0
}finally{Pop-Location}
