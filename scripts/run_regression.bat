@echo off
setlocal EnableExtensions
pushd "%~dp0.."

if not exist sim\rtl mkdir sim\rtl
if not exist sim\cmodel mkdir sim\cmodel
if not exist sim\trace mkdir sim\trace
if not exist sim\logs mkdir sim\logs

set "CORE_FILES=rtl\sr_leaf.v rtl\sr_column.v rtl\sr_direction_fabric.v rtl\sr_hemisphere_fabric.v rtl\sr_fabric.v"

call scripts\run_compile.bat
if errorlevel 1 goto fail

python3 scripts\check_module_names.py
if errorlevel 1 goto fail
python3 scripts\check_dependencies.py
if errorlevel 1 goto fail
python3 scripts\check_dimensions.py
if errorlevel 1 goto fail

call :run_tb tb_sr_reset_semantic
if errorlevel 1 goto fail
echo RESET_SEMANTIC PASS

echo AC1_DEFAULT_HIERARCHY PASS

call :run_tb tb_sr_leaf_semantic
if errorlevel 1 goto fail
call :run_tb tb_sr_leaf_cell_semantic
if errorlevel 1 goto fail
echo AC2_STATE_OWNERSHIP PASS

call :run_tb tb_sr_column_compliance
if errorlevel 1 goto fail
echo AC3_COLUMN_COMPLIANCE PASS

call :run_tb tb_sr_basic_pipeline
if errorlevel 1 goto fail
call :run_tb tb_sr_direction_fabric
if errorlevel 1 goto fail
call :run_tb tb_sr_hemisphere_fabric
if errorlevel 1 goto fail
call :run_tb tb_sr_fabric
if errorlevel 1 goto fail
echo CORE_FUNCTIONAL_REGRESSION PASS

call :run_tb tb_sr_saturated_stream
if errorlevel 1 goto fail
call :run_tb tb_sr_saturated_full_profile
if errorlevel 1 goto fail
echo AC4_SATURATED_STREAM PASS

call :run_tb tb_sr_hop_trace
if errorlevel 1 goto fail
echo AC5_HOP_TIMING PASS

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto cmodel_tool_fail
set "VSROOT="
for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT goto cmodel_tool_fail
call "%VSROOT%\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch=x64 > sim\logs\msvc_environment.log 2>&1
if errorlevel 1 goto cmodel_tool_fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c cmodel\srf_model.cpp /Fo:sim\cmodel\srf_model.obj > sim\logs\cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c cmodel\test_cmodel.cpp /Fo:sim\cmodel\test_cmodel.obj >> sim\logs\cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail
link /NOLOGO /OUT:sim\cmodel\test_cmodel.exe sim\cmodel\srf_model.obj sim\cmodel\test_cmodel.obj >> sim\logs\cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail
sim\cmodel\test_cmodel.exe > sim\logs\cmodel_regression.log 2>&1
if errorlevel 1 goto cmodel_run_fail
type sim\logs\cmodel_regression.log
findstr /C:"TEST_FAIL" sim\logs\cmodel_regression.log >nul
if not errorlevel 1 goto cmodel_run_fail
findstr /X /C:"TEST_PASS" sim\logs\cmodel_regression.log >nul
if errorlevel 1 goto cmodel_run_fail
echo CMODEL_REGRESSION PASS

python3 scripts\compare_rtl_cmodel.py
if errorlevel 1 goto fail

echo SRF REGRESSION PASS
echo SRF REGRESSION TEST_PASS
popd
exit /b 0

:run_tb
set "TB_NAME=%~1"
iverilog -g2012 -Wall -s %TB_NAME% -o sim\rtl\%TB_NAME% %CORE_FILES% tb\%TB_NAME%.v > sim\logs\%TB_NAME%_compile.log 2>&1
if errorlevel 1 goto run_tb_compile_fail
vvp sim\rtl\%TB_NAME% > sim\logs\%TB_NAME%.log 2>&1
if errorlevel 1 goto run_tb_sim_fail
type sim\logs\%TB_NAME%.log
findstr /C:"TEST_FAIL" sim\logs\%TB_NAME%.log >nul
if not errorlevel 1 goto run_tb_sim_fail
findstr /X /C:"TEST_PASS" sim\logs\%TB_NAME%.log >nul
if errorlevel 1 goto run_tb_sim_fail
exit /b 0

:run_tb_compile_fail
type sim\logs\%TB_NAME%_compile.log
echo %TB_NAME% COMPILE_FAIL
exit /b 1

:run_tb_sim_fail
type sim\logs\%TB_NAME%.log
echo %TB_NAME% TEST_FAIL
exit /b 1

:cmodel_compile_fail
type sim\logs\cmodel_compile.log
echo CMODEL_REGRESSION FAIL
goto fail

:cmodel_tool_fail
echo ERROR MSVC C++ build tools were not found.
echo CMODEL_REGRESSION FAIL
goto fail

:cmodel_run_fail
type sim\logs\cmodel_regression.log
echo CMODEL_REGRESSION FAIL
goto fail

:fail
echo SRF REGRESSION TEST_FAIL
popd
exit /b 1
