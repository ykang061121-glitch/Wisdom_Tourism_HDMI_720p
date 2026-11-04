$ErrorActionPreference='Stop'
$script:ProjectRoot=Split-Path $PSScriptRoot -Parent
$script:Hdl=Join-Path $ProjectRoot 'src\user_source\hdl_source'
$cmd=Get-Command vsim.exe -ErrorAction SilentlyContinue
$script:ModelSimBin=if($env:MODELSIM_BIN){$env:MODELSIM_BIN}elseif($cmd){Split-Path $cmd.Source -Parent}else{'D:\modelism10.4\win64'}
foreach($n in 'vlib','vlog','vsim'){if(!(Test-Path -LiteralPath "$ModelSimBin\$n.exe")){throw "Set MODELSIM_BIN; missing $n.exe"}}
$pc=Get-Command python.exe -ErrorAction SilentlyContinue
$script:PythonExe=if($env:PYTHON_EXE){$env:PYTHON_EXE}elseif($pc){$pc.Source}else{'C:\Users\ASUS\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'}
if(!(Test-Path -LiteralPath $PythonExe)){throw 'Set PYTHON_EXE to Python 3 with numpy and Pillow'}
