@echo off
setlocal enabledelayedexpansion

echo ========================================
echo  Lycoris Control - MSI Builder
echo ========================================
echo.

:: Change to project root (batch file location)
cd /d "%~dp0.."

:: --- CONFIG ---
set "APP_NAME=Lycoris_Control"
set "PRODUCT_NAME=Lycoris Control"
set "COMPANY=Reidchend"
set "DIST_DIR=dist\%APP_NAME%"
set "WIX_DIR=wix"
set "OUTPUT_MSI=dist\%APP_NAME%.msi"

:: Check if dist folder exists
if not exist "%DIST_DIR%" (
    echo [ERROR] Folder not found: %DIST_DIR%
    echo.
    echo Run PyInstaller first:
    echo   pyinstaller --noconfirm --onedir --windowed --name "%APP_NAME%" --icon "assets/icono.ico" --add-data "assets;assets" --add-data ".env;." --collect-all "supabase" --collect-all "pydantic_settings" --collect-submodules "sqlalchemy" --hidden-import "sqlalchemy.dialects.postgresql" --hidden-import "pg8000" main.py
    pause
    exit /b 1
)

:: Read version from version.json (fallback to 1.0.0)
set "VERSION=1.0.0"
if exist version.json (
    for /f "tokens=2 delims=:, " %%a in ('findstr "version" version.json') do (
        set "VERSION=%%~a"
        set "VERSION=!VERSION:"=!
        goto :version_found
    )
)
:version_found
echo [INFO] Version: !VERSION!
echo [INFO] Source: %DIST_DIR%
echo.

:: --- STEP 1: Heat - Harvest files from dist ---
echo [1/4] Harvesting files with heat.exe...
if not exist "%WIX_DIR%" mkdir "%WIX_DIR%"

heat.exe dir "%DIST_DIR%" ^
    -cg HarvestedFiles ^
    -gg ^
    -scom ^
    -sfrag ^
    -srd ^
    -suid ^
    -dr INSTALLDIR ^
    -var var.SourceDir ^
    -out "%WIX_DIR%\heat.wxs" ^
    -sw1070

if %errorlevel% neq 0 (
    echo [ERROR] heat.exe failed. Make sure WIX Toolset is installed.
    pause
    exit /b 1
)
echo [OK] heat.wxs generated.
echo.

:: --- STEP 2: Candle - Compile WXS files ---
echo [2/4] Compiling with candle.exe...
candle.exe "%WIX_DIR%\installer.wxs" ^
    -dSourceDir="%DIST_DIR%" ^
    -dProductVersion="!VERSION!" ^
    -arch x64 ^
    -out "%WIX_DIR%\installer.wixobj"

if %errorlevel% neq 0 (
    echo [ERROR] candle.exe failed for installer.wxs
    pause
    exit /b 1
)

candle.exe "%WIX_DIR%\heat.wxs" ^
    -dSourceDir="%DIST_DIR%" ^
    -arch x64 ^
    -out "%WIX_DIR%\heat.wixobj"

if %errorlevel% neq 0 (
    echo [ERROR] candle.exe failed for heat.wxs
    pause
    exit /b 1
)
echo [OK] WIX objects compiled.
echo.

:: --- STEP 3: Light - Link to MSI ---
echo [3/4] Linking with light.exe...
light.exe "%WIX_DIR%\installer.wixobj" "%WIX_DIR%\heat.wixobj" ^
    -ext WixUIExtension ^
    -out "%OUTPUT_MSI%" ^
    -sw1076

if %errorlevel% neq 0 (
    echo [ERROR] light.exe failed.
    pause
    exit /b 1
)
echo [OK] MSI created.
echo.

:: --- STEP 4: Cleanup intermediates ---
echo [4/4] Cleaning up intermediate files...
if exist "%WIX_DIR%\installer.wixobj" del "%WIX_DIR%\installer.wixobj"
if exist "%WIX_DIR%\heat.wixobj" del "%WIX_DIR%\heat.wixobj"
if exist "%WIX_DIR%\heat.wxs" del "%WIX_DIR%\heat.wxs"
echo [OK] Cleanup done.
echo.

echo ========================================
echo  SUCCESS!
echo ========================================
echo  MSI: %OUTPUT_MSI%
echo  Version: !VERSION!
echo ========================================
echo.

pause
