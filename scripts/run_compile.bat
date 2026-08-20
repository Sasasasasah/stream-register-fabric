@echo off
setlocal EnableExtensions
pushd "%~dp0.."

if not exist sim\rtl mkdir sim\rtl
if not exist sim\logs mkdir sim\logs

set "CORE_FILES=rtl\sr_leaf.v rtl\sr_column.v rtl\sr_direction_fabric.v rtl\sr_hemisphere_fabric.v rtl\sr_fabric.v"

iverilog -g2012 -Wall -s tb_sr_default_profile -o sim\rtl\tb_sr_core_compile %CORE_FILES% tb\tb_sr_default_profile.v > sim\logs\core_compile.log 2>&1
if errorlevel 1 goto fail_compile

vvp sim\rtl\tb_sr_core_compile > sim\logs\core_compile_run.log 2>&1
if errorlevel 1 goto fail_run
type sim\logs\core_compile_run.log
findstr /C:"TEST_FAIL" sim\logs\core_compile_run.log >nul
if not errorlevel 1 goto fail_run
findstr /X /C:"TEST_PASS" sim\logs\core_compile_run.log >nul
if errorlevel 1 goto fail_run

echo CORE_COMPILE PASS
echo DEFAULT_PROFILE_REGRESSION TEST_PASS
popd
exit /b 0

:fail_compile
type sim\logs\core_compile.log
echo CORE_COMPILE FAIL
popd
exit /b 1

:fail_run
type sim\logs\core_compile_run.log
echo CORE_COMPILE FAIL
popd
exit /b 1
