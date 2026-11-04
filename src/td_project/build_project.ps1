param([switch]$Implement)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$tdhome=if($env:TD_HOME){$env:TD_HOME}else{'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116'}
$td=Join-Path $tdhome 'bin\td_commands_prompt.exe'
$py=if($env:PYTHON_EXE){$env:PYTHON_EXE}else{(Get-Command python.exe -ErrorAction Stop).Source}
if(!(Test-Path -LiteralPath $td)){throw 'Set TD_HOME to TD 6.2.168116'}
function Run-TD([string]$Cwd,[string]$Script,[string]$Log){
 Push-Location -LiteralPath $Cwd
 try{& $td ($Script -replace '\\','/') *> $Log;$code=$LASTEXITCODE;$text=Get-Content -LiteralPath $Log -Raw;if($code -or $text-match '\bERROR:|\bError:'){throw "TD failed: $Log"}}finally{Pop-Location}
}
$runs=Join-Path $PSScriptRoot 'HDMI1.4b_Transmitter_v1.0_Runs'
Run-TD "$runs\syn_1" "$tdhome\doc\scripts\DefaultFlow.tcl" 'rebuild_synthesis.log'
if(!$Implement){Write-Output 'Synthesis complete. Use -Implement only for a new experimental implementation; known hardware bit is in output/.';exit 0}
Run-TD "$runs\phy_1" "$tdhome\doc\scripts\DefaultFlow.tcl" 'rebuild_physical.log'
Run-TD "$runs\phy_1" "$PSScriptRoot\scripts\export_route.tcl" 'rebuild_export.log'
& $py -X utf8 "$PSScriptRoot\scripts\verify_reset_binding.py"
if($LASTEXITCODE){throw 'Reset identity changed; no exception edited and finalization stopped'}
Run-TD "$runs\phy_1" "$PSScriptRoot\scripts\finalize_original.tcl" 'rebuild_final_sta.log'
Write-Output 'New implementation is experimental until Final STA review and separate hardware acceptance. Original delivered bit in output/ is never overwritten.'
