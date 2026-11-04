[CmdletBinding()]
param([switch]$SkipBaseline,[switch]$ProbeVendorSDRAM)
$ErrorActionPreference='Stop'
$started=Get-Date -Format o
$root=Split-Path -Parent $PSScriptRoot
$hdl=Join-Path $root 'src\user_source\hdl_source'
$tool=Get-Command vsim.exe -ErrorAction SilentlyContinue
$bin=if($env:MODELSIM_BIN){$env:MODELSIM_BIN}elseif($tool){Split-Path -Parent $tool.Source}else{'D:\modelism10.4\win64'}
foreach($name in 'vlib','vlog','vsim'){if(!(Test-Path -LiteralPath "$bin\$name.exe")){throw "Missing simulator $bin\$name.exe"}}
if(!$SkipBaseline){& "$PSScriptRoot\run_tests.ps1";if($LASTEXITCODE){exit $LASTEXITCODE}}
$build=Join-Path $PSScriptRoot 'build\reliability'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$results=@()
Push-Location $build
try {
    & "$bin\vlib.exe" work *> vlib.log
    if($LASTEXITCODE){throw 'vlib failed'}
    $sources=@('osd_status_cdc.v','melody_status_cdc.v','image_audio_cdc.v','frame_completion_guard.v','fade_transition_cdc.v','fade_transition_ctrl.v') | ForEach-Object {Join-Path $hdl $_}
    & "$bin\vlog.exe" -sv @sources "$PSScriptRoot\tb_reliability_cdc.v" *> compile.log
    if($LASTEXITCODE){throw 'reliability compile failed; see sim/build/reliability/compile.log'}
    foreach($phase in 0,7,19,39){
        $log="phase_$phase.log"
        & "$bin\vsim.exe" -c work.tb_reliability_cdc "+PHASE=$phase" -do 'run -all; quit -f' *> $log
        $code=$LASTEXITCODE;$text=Get-Content $log -Raw
        $pass=($code -eq 0 -and $text.Contains('RELIABILITY_CDC_TEST_PASS') -and $text -notmatch 'Fatal:|\*\* Error:')
        $results += [pscustomobject]@{Name="reliability CDC phase $phase";Passed=$pass;ExitCode=$code;Log=(Join-Path $build $log)}
        Write-Host "$(if($pass){'PASS'}else{'FAIL'}) reliability CDC phase $phase"
    }
    foreach($fault in 'TORN_CDC','EARLY_READY'){
        $log="negative_$fault.log"
        & "$bin\vsim.exe" -c work.tb_reliability_cdc "+INJECT_$fault" -do 'run -all; quit -f' *> $log
        $code=$LASTEXITCODE;$text=Get-Content $log -Raw
        $pass=$text.Contains('RELIABILITY_CHECKER_REJECT') -and !$text.Contains('RELIABILITY_CDC_TEST_PASS')
        $results += [pscustomobject]@{Name="negative reliability $fault";Passed=$pass;ExitCode=$code;Log=(Join-Path $build $log)}
        Write-Host "$(if($pass){'PASS'}else{'FAIL'}) negative reliability $fault"
    }
    $probe='NotRun'
    if($ProbeVendorSDRAM){
        $tdModel='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\sim_release\eg4\eg_phy_sdram_2m_32.v'
        if(!(Test-Path -LiteralPath $tdModel)){throw "Missing vendor model $tdModel"}
        # Preserve the vendor header's ../user_source/... include convention.
        # Legacy vendor model uses an unsized concatenation. Keep its diagnostic
        # visible as a warning; do not edit encrypted source or suppress checks.
        & "$bin\vlog.exe" -sv -permissive "+incdir+$hdl\include" "+incdir+$root\src\td_project" "$hdl\include\sdr_init_ref.enc.v" "$hdl\include\sdr_wrrd.enc.v" "$hdl\include\sdr_as_ram.enc.v" $tdModel "$PSScriptRoot\tb_sdram_vendor_probe.v" *> vendor_compile.log
        if($LASTEXITCODE){$probe='UNAVAILABLE_COMPILE'}else{
            & "$bin\vsim.exe" -c work.tb_sdram_vendor_probe -do 'run -all; quit -f' *> vendor_run.log
            $probeCode=$LASTEXITCODE;$text=Get-Content vendor_run.log -Raw
            $probe=if($probeCode -eq 0 -and $text.Contains('VENDOR_SDRAM_PROBE_PASS')){'PASS'}else{'UNAVAILABLE_OR_FAILED'}
        }
        Write-Host "Vendor SDRAM capability probe: $probe (not counted as functional PASS unless marker present)"
        [pscustomobject]@{FinishedAt=(Get-Date -Format o);Result=$probe;
            CompileLog=(Join-Path $build 'vendor_compile.log');RunLog=(Join-Path $build 'vendor_run.log');
            Note='ModelSim -permissive used only for the legacy vendor unsized concatenation; diagnostic retained.'} |
            ConvertTo-Json | Set-Content -LiteralPath vendor_probe_summary.json -Encoding UTF8
    }
    [pscustomobject]@{StartedAt=$started;FinishedAt=(Get-Date -Format o);Simulator="$bin\vsim.exe";
        Results=$results;VendorSDRAMProbe=$probe;
        SourceHashes=@(($sources + "$PSScriptRoot\tb_reliability_cdc.v") | Get-FileHash);
        Scope='RTL digital protocol only; no metastability, PVT or electrical chip signoff'} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath summary.json -Encoding UTF8
    if(@($results | Where-Object {!$_.Passed}).Count){exit 1}
    if($ProbeVendorSDRAM -and $probe -ne 'PASS'){exit 2}
    exit 0
} finally {Pop-Location}
