param([switch]$Synthesize)
. "$PSScriptRoot\tool_paths.ps1"
$env:PYTHON_EXE=$PythonExe
& $PythonExe -X utf8 "$PSScriptRoot\check_project.py"
if($LASTEXITCODE){throw 'Dependency identity check failed'}
& "$PSScriptRoot\run_tests.ps1" *> "$PSScriptRoot\legacy_latest.log"
$j=Get-Content -LiteralPath "$PSScriptRoot\build\regression_summary.json" -Raw|ConvertFrom-Json
$expected=@('picture transitions','advanced video','playback recovery','two alternating transitions','tourism video')|Sort-Object
$actual=@($j.Results|Where-Object {!$_.Passed}|ForEach-Object {$_.Name})|Sort-Object
if(($expected-join '|')-ne($actual-join '|')){throw "Unexpected historical regression result; see sim/legacy_latest.log: $($actual-join ', ')"}
Write-Output 'Original 52 tests retained. Five known legacy effect-coverage incompatibilities recorded, not counted as PASS.'
foreach($s in 'cdc','controls','scaling','osd','pcm','transitions','protocol'){
 & "$PSScriptRoot\run_current_tests.ps1" -Suite $s
}
& "$PSScriptRoot\current\spectrum\run_tests.ps1"
if($Synthesize){& "$ProjectRoot\src\td_project\build_project.ps1";if($LASTEXITCODE){throw 'TD synthesis failed'}}
Write-Output 'Current-design verification finished. Read known historical test incompatibilities and timing risks; no JTAG/Flash/card operations were performed.'
