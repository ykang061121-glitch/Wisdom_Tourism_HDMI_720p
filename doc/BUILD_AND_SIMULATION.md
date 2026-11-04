# 构建与仿真

## 环境

- Windows，安路Tang Dynasty 6.2.168116，EG4S20BG256器件支持。
- ModelSim 10.4；Python 3.10或以上，`numpy`和`Pillow`。
- 可通过环境变量设置 `TD_HOME`、`MODELSIM_BIN`、`PYTHON_EXE`。脚本中的D盘工具路径仅作为原开发机可选回退，不引用其他历史工程。
- 本工程没有附带商业软件或许可证；需使用已授权安装的厂商工具和IP。

## 先核验输入

```powershell
python .\sim\check_project.py
```

校验139项生产输入、已验证bit、AL/PRJ文件引用、约束与Verilog include。工程文件、素材和仿真输入均位于本目录内，移到其他位置后以当前目录为工作根执行。

## 仿真

```powershell
$env:MODELSIM_BIN='你的ModelSim目录\win64'
$env:TD_HOME='你的TD安装目录'
$env:PYTHON_EXE='你的Python完整路径'
.\sim\run_verify.ps1
```

统一入口依次运行原始回归、四相位CDC及故障注入、参数与按键、12种实际BMP、三缩放核心模式、完整OSD像素、真实PCM到UI、两轮FADE/SLIDE、HDMI视频及音频数字协议、DFT独立数学参考。输出在sim/build及各current测试的运行目录，新验证不覆盖doc/verification中本次提交核验记录。

原始52项功能中5项fixture仍要求已经停用的FADE/WIPE序列，其不适配预计失败。统一入口严格核对失败项名称；出现其他失败会停止。当前FADE/SLIDE由独立的270整帧检查替代覆盖，原断言保留，五项未改记为PASS。

也可单独运行：

```powershell
.\sim\run_current_tests.ps1 -Suite controls
.\sim\run_current_tests.ps1 -Suite scaling
.\sim\run_current_tests.ps1 -Suite osd
.\sim\run_current_tests.ps1 -Suite transitions
.\sim\run_current_tests.ps1 -Suite pcm
.\sim\run_current_tests.ps1 -Suite protocol   # 先运行osd以产生真实RTL帧
.\sim\current\spectrum\run_tests.ps1
```

运行目录已有result.json时，部分定向fixture会拒绝覆盖；需要重复时在重新解压的独立副本运行。Python仅转换或比较真实RTL数据，没有绘制伪UI。

## TD综合与实现

图形入口：`src/td_project/HDMI1.4b_Transmitter_v1.0.al`。AL入口从实测版本PRJ源清单恢复，外壳沿用官方AL，139项原始生产输入仍完全不变。

```powershell
.\src\td_project\build_project.ps1
.\src\td_project\build_project.ps1 -Implement
```

第一条只综合。第二条才执行Place/Route、复位入口身份验证及原Final STA/hold修正流程。原设置、频率、ADC/SDC和seed不变。新物理网表的复位SR身份不符合原边界时会停止，不自动改写SDC，也不沿用不匹配的例外。

重新实现的bit属于新实现结果，需重新审核STA和实体测试，不能因为源码相同就称为已验证的配置。原实测bit始终单独保存在output，不被构建脚本覆盖。本次打包只重新完成综合与仿真，没有再次P&R或新生成bit；implementation目录的Final STA属于已实测配置对应的原始实现。

## 仿真边界

生产顶层沿用TD可接受的前向信号声明，ModelSim对完整顶层直接编译会报声明顺序问题；本次保留失败日志，没有改动生产RTL。完整顶层编译由本次TD综合验证，ModelSim用于实际子系统、完整像素图层、真实BMP与HDMI加密核协议检查。SDRAM由受控服务模型辅助验证，不能代替SiP真实电气、刷新和完整物理行为签核。
